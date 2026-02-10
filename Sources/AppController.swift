import Foundation
import AVFoundation
import AppKit
import UniformTypeIdentifiers

final class AppController {
    private let stateQueue = DispatchQueue(label: "app.state.queue")

    let settings: SettingsManager
    let statePublisher: AppStatePublisher

    private var state: AppState = .idle
    private var mode: CaptureMode?
    private var audio = AudioCapture()
    private var asr: ASRWebSocketClient?
    private var fileAsr: FileASRStreamClient?
    private let transcript = TranscriptBuffer()
    private let clipboard = ClipboardWriter()
    private let typer = RealtimeTyper()
    private var stopTimeoutWork: DispatchWorkItem?
    private var autoStopWork: DispatchWorkItem?
    private var lastHotkeyAt = Date.distantPast
    private var recordedPCM = Data()
    private var recordStartedAt = Date.distantPast
    private var fileStreamText = ""
    private let llmService = LLMService()
    private(set) lazy var lectureController = LectureController(
        settings: settings, statePublisher: statePublisher,
        sessionManager: sessionManager, llmService: llmService
    )
    private var keyTapActive = false
    private var permissionTimer: Timer?
    private var permissionSnapshot = PermissionSnapshot(microphone: false, accessibility: false, inputMonitoring: false)
    var onPermissionChanged: ((PermissionSnapshot) -> Void)?
    private var partialStabilizeWork: DispatchWorkItem?
    private var pendingPartialText = ""
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 2
    private var reconnectWork: DispatchWorkItem?
    private var lastFailedFileAudioURL: URL?
    private var lastTransformUndoText: String?
    private var lastTransformUndoSession: TranscriptionSession?

    // v4: Session management
    private var currentSession: TranscriptionSession?
    private let sessionManager = SessionManager.shared

    var recordingIndicator: RecordingIndicatorController?

    private lazy var keyTap = GlobalKeyTap(settings: settings) { [weak self] action in
        self?.handleTrigger(action)
    }

    init(settings: SettingsManager, statePublisher: AppStatePublisher) {
        self.settings = settings
        self.statePublisher = statePublisher
    }

    func setCurrentSession(_ session: TranscriptionSession) {
        currentSession = session
    }

    func getCurrentSession() -> TranscriptionSession? {
        currentSession
    }

    func start() {
        lectureController.appController = self
        Console.line("FlashASR started.")
        Console.line("Onboarding completed: \(settings.hasCompletedOnboarding)")
        Console.line("State: IDLE")
        refreshPermissions(startup: true)
        startPermissionTimer()

        // Listen for menu-triggered actions
        NotificationCenter.default.addObserver(forName: .triggerRealtime, object: nil, queue: .main) { [weak self] _ in
            self?.handleTrigger(.realtimeToggle)
        }
        NotificationCenter.default.addObserver(forName: .triggerFile, object: nil, queue: .main) { [weak self] _ in
            self?.handleTrigger(.fileToggle)
        }
        NotificationCenter.default.addObserver(forName: .retryFailedFileUpload, object: nil, queue: .main) { [weak self] _ in
            self?.retryLastFailedFileUpload()
        }
        // v4 notifications
        NotificationCenter.default.addObserver(forName: .continueRecording, object: nil, queue: .main) { [weak self] note in
            let rawMode = (note.userInfo?["mode"] as? Int) ?? 0
            let captureMode: CaptureMode = rawMode == 1 ? .fileFlash : .realtime
            self?.continueRecording(mode: captureMode)
        }
        NotificationCenter.default.addObserver(forName: .saveToObsidian, object: nil, queue: .main) { [weak self] _ in
            self?.saveToObsidian()
        }
        NotificationCenter.default.addObserver(forName: .fullRefinement, object: nil, queue: .main) { [weak self] note in
            let rawLevel = (note.userInfo?["level"] as? Int) ?? self?.settings.defaultMarkdownLevel ?? 1
            if let level = MarkdownLevel(rawValue: rawLevel) {
                self?.triggerFullRefinement(level: level)
            }
        }
        NotificationCenter.default.addObserver(forName: .switchMarkdownLevel, object: nil, queue: .main) { [weak self] note in
            if let rawLevel = note.userInfo?["level"] as? Int,
               let level = MarkdownLevel(rawValue: rawLevel) {
                self?.switchMarkdownLevel(level)
            }
        }
        NotificationCenter.default.addObserver(forName: .openSession, object: nil, queue: .main) { [weak self] note in
            if let idStr = note.userInfo?["id"] as? String,
               let uuid = UUID(uuidString: idStr) {
                self?.loadSession(uuid)
            }
        }
        NotificationCenter.default.addObserver(forName: .deleteSession, object: nil, queue: .main) { [weak self] note in
            if let idStr = note.userInfo?["id"] as? String,
               let uuid = UUID(uuidString: idStr) {
                self?.deleteSession(uuid)
            }
        }
        // v4.1 text upload notifications
        NotificationCenter.default.addObserver(forName: .processClipboardText, object: nil, queue: .main) { [weak self] _ in
            self?.processClipboardText()
        }
        NotificationCenter.default.addObserver(forName: .processFileText, object: nil, queue: .main) { [weak self] _ in
            self?.processFileText()
        }
        NotificationCenter.default.addObserver(forName: .processManualText, object: nil, queue: .main) { [weak self] note in
            let raw = (note.userInfo?["text"] as? String) ?? ""
            let levelRaw = (note.userInfo?["level"] as? Int) ?? self?.settings.defaultMarkdownLevel ?? 1
            let level = MarkdownLevel(rawValue: levelRaw) ?? .light
            self?.lastTransformUndoText = self?.statePublisher.editableText
            self?.lastTransformUndoSession = self?.currentSession
            self?.statePublisher.canUndoTransform = true
            self?.processUploadedText(raw, level: level)
        }
        NotificationCenter.default.addObserver(forName: .undoTransform, object: nil, queue: .main) { [weak self] _ in
            self?.undoLastTransform()
        }
        // v6.0 export
        NotificationCenter.default.addObserver(forName: .exportSession, object: nil, queue: .main) { [weak self] note in
            let formatStr = (note.userInfo?["format"] as? String) ?? "md"
            let format = ExportFormat(rawValue: formatStr) ?? .markdown
            self?.exportSession(format: format)
        }
        NotificationCenter.default.addObserver(forName: .importLectureAudio, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.lectureController.importAudio(currentSession: &self.currentSession)
        }
        NotificationCenter.default.addObserver(forName: .generateLectureNote, object: nil, queue: .main) { [weak self] note in
            let raw = (note.userInfo?["mode"] as? String) ?? LectureNoteMode.lessonPlan.rawValue
            let mode = LectureNoteMode(rawValue: raw) ?? .lessonPlan
            self?.lectureController.generateNote(mode: mode, currentSession: self?.currentSession)
        }
        NotificationCenter.default.addObserver(forName: .retryLectureSegment, object: nil, queue: .main) { [weak self] note in
            guard let idx = note.userInfo?["index"] as? Int else { return }
            self?.lectureController.retrySegment(index: idx, currentSession: self?.currentSession)
        }
        NotificationCenter.default.addObserver(forName: .cancelLectureImport, object: nil, queue: .main) { [weak self] _ in
            self?.lectureController.cancelImport()
        }
        NotificationCenter.default.addObserver(forName: .startLectureRecording, object: nil, queue: .main) { [weak self] _ in
            self?.lectureController.startRecording()
        }
        NotificationCenter.default.addObserver(forName: .finishLectureRecording, object: nil, queue: .main) { [weak self] _ in
            self?.lectureController.finishLectureRecording()
        }
        NotificationCenter.default.addObserver(forName: .renameSession, object: nil, queue: .main) { [weak self] note in
            guard let idStr = note.userInfo?["id"] as? String,
                  let uuid = UUID(uuidString: idStr),
                  let title = note.userInfo?["title"] as? String else { return }
            self?.renameSession(uuid, title: title)
        }
        NotificationCenter.default.addObserver(forName: .completeLectureProfile, object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let profile = note.userInfo?["profile"] as? CourseProfile else { return }
            let url = self.statePublisher.pendingLectureURL
            self.statePublisher.showCourseProfileSheet = false
            self.statePublisher.pendingLectureURL = nil
            if let url {
                // Import mode
                self.lectureController.completeLectureImport(url: url, profile: profile, currentSession: &self.currentSession)
            } else {
                // Real-time lecture mode
                self.lectureController.beginLectureSession(profile: profile, currentSession: &self.currentSession)
                self.stateQueue.async {
                    self.beginListening(mode: .realtime)
                }
            }
        }
    }

    func handleTrigger(_ action: TriggerAction) {
        stateQueue.async {
            guard self.permissionSnapshot.allGranted || self.settings.permissionTrustOverride else {
                self.publishError("Permissions not ready. Open Permissions Guide and grant all required permissions.")
                return
            }
            let now = Date()
            if now.timeIntervalSince(self.lastHotkeyAt) < 0.25 {
                return
            }
            self.lastHotkeyAt = now

            switch action {
            case .realtimeToggle:
                self.routeToggle(for: .realtime, startLabel: "Realtime hotkey -> start", stopLabel: "Realtime hotkey -> stop")
            case .fileToggle:
                self.routeToggle(for: .fileFlash, startLabel: "File hotkey -> start", stopLabel: "File hotkey -> stop")
            }
        }
    }

    func pauseHotkeys() {
        keyTap.pause()
    }

    func resumeHotkeys() {
        keyTap.resume()
    }

    func stopFromIndicator() {
        stateQueue.async {
            guard self.state == .listening else { return }
            self.beginStopping(reason: "Indicator stop")
        }
    }

    func copyLastFinalToClipboard() {
        DispatchQueue.main.async {
            let text = self.statePublisher.lastFinalText
            guard !text.isEmpty else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
    }

    private func publishState(_ newState: AppState, mode: CaptureMode? = nil) {
        DispatchQueue.main.async {
            self.statePublisher.state = newState
            self.statePublisher.mode = mode
        }
    }

    private func publishTranscript(_ text: String) {
        DispatchQueue.main.async {
            self.statePublisher.currentTranscript = text
        }
    }

    private func publishError(_ msg: String?) {
        DispatchQueue.main.async {
            self.statePublisher.errorMessage = msg
        }
    }

    private func routeToggle(for targetMode: CaptureMode, startLabel: String, stopLabel: String) {
        switch state {
        case .idle:
            Console.line(startLabel)
            // New hotkey press starts a brand new session
            currentSession = nil
            beginListening(mode: targetMode)
        case .listening:
            guard mode == targetMode else {
                Console.line("Ignoring hotkey for different mode while listening.")
                return
            }
            Console.line(stopLabel)
            beginStopping(reason: "Manual stop")
        case .stopping:
            break
        }
    }

    private func beginListening(mode: CaptureMode) {
        guard permissionSnapshot.allGranted || settings.permissionTrustOverride else {
            publishError("Permissions not ready. Please grant Microphone, Accessibility, and Input Monitoring.")
            return
        }
        let apiKey = settings.effectiveDashscopeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            publishError("Dashscope API Key is empty. Please configure it in Settings -> API Keys.")
            return
        }
        // Cancel any in-progress LLM requests
        llmService.cancelAll()
        DispatchQueue.main.async {
            self.statePublisher.markdownProcessing = false
            self.statePublisher.markdownText = ""
            self.statePublisher.markdownError = nil
            self.statePublisher.generatingLevel = nil
            self.statePublisher.glmProcessing = false
            self.statePublisher.glmText = ""
            self.statePublisher.showGLMVersion = false
            self.statePublisher.glmGeneratingLevel = nil
        }

        // v4: Create session if none (new recording), keep if continuing
        if currentSession == nil {
            currentSession = sessionManager.createSession()
            if settings.markdownModeEnabled {
                DispatchQueue.main.async {
                    self.statePublisher.currentSession = self.currentSession
                    self.statePublisher.selectedTab = .original
                }
            }
            if let id = currentSession?.id {
                Console.line("Created new session: \(id)")
            }
        }

        self.mode = mode
        state = .listening
        transcript.reset()
        fileStreamText = ""
        recordedPCM.removeAll(keepingCapacity: true)
        recordStartedAt = Date()
        reconnectAttempts = 0
        reconnectWork?.cancel()
        reconnectWork = nil
        partialStabilizeWork?.cancel()
        partialStabilizeWork = nil
        pendingPartialText = ""
        // Skip realtime typing when Markdown mode is on
        let enableTyping = settings.realtimeTypeEnabled && !settings.markdownModeEnabled
        typer.prepareForSession(realtimeTypeEnabled: enableTyping)
        stopTimeoutWork?.cancel()
        stopTimeoutWork = nil
        autoStopWork?.cancel()
        autoStopWork = nil

        publishState(.listening, mode: mode)
        publishTranscript("")
        DispatchQueue.main.async {
            self.statePublisher.remainingRecordSeconds = mode == .fileFlash ? 300 : nil
            self.statePublisher.audioLevel = 0.0
        }

        Console.clearPartialLine()
        switch mode {
        case .realtime:
            Console.line("State: LISTENING (realtime ASR connecting...)")
        case .fileFlash:
            Console.line("State: LISTENING (file ASR recording, max 5 min...)")
        }

        // Show recording indicator
        DispatchQueue.main.async {
            self.recordingIndicator?.show(state: self.statePublisher)
        }

        // v4: Wire audio level callback
        audio.onAudioLevel = { [weak self] level in
            DispatchQueue.main.async {
                self?.statePublisher.audioLevel = level
            }
        }

        let continueStart: () -> Void = { [weak self] in
            guard let self else { return }
            guard self.state == .listening, self.mode == mode else { return }

            switch mode {
            case .realtime:
                guard let wsURL = URL(string: self.settings.wsBaseURL) else {
                    Console.line("Invalid realtime WS URL")
                    self.state = .idle
                    self.mode = nil
                    self.publishState(.idle)
                    return
                }
                let client = ASRWebSocketClient(
                    apiKey: self.settings.effectiveDashscopeAPIKey,
                    url: wsURL,
                    model: self.settings.model,
                    language: self.settings.language
                )
                self.asr = client
                client.onEvent = { [weak self] event in
                    self?.handleASREvent(event)
                }
                Console.line("Connecting realtime WebSocket...")
                client.connect()
            case .fileFlash:
                do {
                    try self.audio.start(dropSilenceFrames: false) { [weak self] frame in
                        self?.handleFileFrame(frame)
                    }
                    Console.line("File mode recording started.")
                } catch {
                    Console.line("Audio start failed: \(error.localizedDescription)")
                    self.finalizeAndReset(reason: "Audio start failure")
                }
            }
        }

        continueStart()
    }

    private func handleFileFrame(_ frame: Data) {
        stateQueue.async {
            guard self.state == .listening, self.mode == .fileFlash else { return }
            self.recordedPCM.append(frame)
            let elapsed = Date().timeIntervalSince(self.recordStartedAt)
            let maxSeconds = 300.0
            let remain = max(0, Int(maxSeconds - elapsed))
            DispatchQueue.main.async {
                self.statePublisher.remainingRecordSeconds = remain
            }
            if elapsed >= maxSeconds {
                self.beginStopping(reason: "Reached 5 minute limit")
            }
        }
    }

    private func beginStopping(reason: String) {
        guard state == .listening else { return }
        state = .stopping

        publishState(.stopping, mode: mode)
        Console.line("State: STOPPING (\(reason))")
        autoStopWork?.cancel()
        autoStopWork = nil
        audio.stop()
        if mode == .realtime {
            asr?.endSession()
            let work = DispatchWorkItem { [weak self] in
                self?.finalizeAndReset(reason: "Realtime finalize timeout")
            }
            stopTimeoutWork = work
            stateQueue.asyncAfter(deadline: .now() + 2.0, execute: work)
            return
        }

        doStartFileASRStreaming()

        let work = DispatchWorkItem { [weak self] in
            self?.finalizeAndReset(reason: "File ASR timeout", overrideFinal: self?.fileStreamText ?? "")
        }
        stopTimeoutWork = work
        stateQueue.asyncAfter(deadline: .now() + 90.0, execute: work)
    }

    private func doStartFileASRStreaming() {
        guard mode == .fileFlash else { return }
        guard !recordedPCM.isEmpty else {
            finalizeAndReset(reason: "No recorded audio", overrideFinal: "")
            return
        }
        guard let endpoint = URL(string: settings.fileASRURL) else {
            finalizeAndReset(reason: "Invalid File ASR URL", overrideFinal: "")
            return
        }
        let wav = makeWav(pcm16Mono16k: recordedPCM, sampleRate: Int(kSampleRate), channels: Int(kChannels))
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("FlashASR-failed-\(Int(Date().timeIntervalSince1970)).wav")
        try? wav.write(to: tmpURL)
        lastFailedFileAudioURL = tmpURL
        let base64 = wav.base64EncodedString()
        let durationSec = Double(recordedPCM.count) / Double(Int(kSampleRate) * MemoryLayout<Int16>.size)
        Console.line(String(format: "Recorded audio: %.2fs, %d bytes PCM", durationSec, recordedPCM.count))
        Console.line("Uploading recorded audio to file ASR (streaming response)...")

        let client = FileASRStreamClient(
            apiKey: settings.effectiveDashscopeAPIKey,
            endpoint: endpoint,
            model: settings.fileModel,
            language: settings.language
        )
        fileAsr = client
        client.onDelta = { [weak self] delta in
            self?.stateQueue.async {
                guard let self, self.state == .stopping, self.mode == .fileFlash else { return }
                self.fileStreamText += delta
                Console.partial(self.fileStreamText)
                self.typer.apply(text: self.fileStreamText)
                self.publishTranscript(self.fileStreamText)
            }
        }
        client.onError = { [weak self] msg in
            self?.stateQueue.async {
                Console.line(msg)
                self?.publishError(msg)
            }
        }
        client.onDone = { [weak self] in
            self?.stateQueue.async {
                guard let self, self.state == .stopping, self.mode == .fileFlash else { return }
                if !self.fileStreamText.isEmpty {
                    self.lastFailedFileAudioURL = nil
                }
                self.finalizeAndReset(reason: "File ASR stream finished", overrideFinal: self.fileStreamText)
            }
        }
        client.start(base64Wav: base64)
    }

    private func handleASREvent(_ event: ASREvent) {
        stateQueue.async {
            switch event {
            case .opened:
                guard self.state == .listening, self.mode == .realtime else { return }
                Console.line("WebSocket opened.")
                do {
                    try self.audio.start(dropSilenceFrames: true) { [weak self] frame in
                        self?.asr?.sendAudioFrame(frame)
                    }
                    Console.line("ASR connected, mic streaming...")
                } catch {
                    Console.line("Audio start failed: \(error.localizedDescription)")
                    self.finalizeAndReset(reason: "Audio start failure")
                }

            case .partial(let text):
                guard (self.state == .listening || self.state == .stopping), self.mode == .realtime else { return }
                if self.settings.punctuationStabilizationEnabled {
                    self.pendingPartialText = text
                    self.partialStabilizeWork?.cancel()
                    let delay = self.settings.punctuationStabilizationDelayMs / 1000.0
                    let work = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        self.transcript.handlePartial(self.pendingPartialText) { merged in
                            Console.partial(merged)
                            self.typer.apply(text: merged)
                            self.publishTranscript(merged)
                        }
                    }
                    self.partialStabilizeWork = work
                    self.stateQueue.asyncAfter(deadline: .now() + delay, execute: work)
                } else {
                    self.transcript.handlePartial(text) { merged in
                        Console.partial(merged)
                        self.typer.apply(text: merged)
                        self.publishTranscript(merged)
                    }
                }

            case .final(let text):
                guard (self.state == .listening || self.state == .stopping), self.mode == .realtime else { return }
                self.partialStabilizeWork?.cancel()
                self.partialStabilizeWork = nil
                self.transcript.handleFinal(text) { merged in
                    Console.partial(merged)
                    self.typer.apply(text: merged)
                    self.publishTranscript(merged)
                }

            case .speechStarted:
                guard self.mode == .realtime else { return }
                self.autoStopWork?.cancel()
                self.autoStopWork = nil

            case .speechStopped:
                guard self.state == .listening, self.mode == .realtime, self.settings.autoStopEnabled else { return }
                self.autoStopWork?.cancel()
                let delay = self.settings.autoStopDelay
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    if self.state == .listening {
                        self.beginStopping(reason: "Auto stop after speech end")
                    }
                }
                self.autoStopWork = work
                self.stateQueue.asyncAfter(deadline: .now() + delay, execute: work)

            case .transcriptionFailed(let msg):
                Console.line("ASR transcription failed: \(msg)")
                self.publishError(msg)

            case .sessionFinished:
                if self.state == .stopping, self.mode == .realtime {
                    self.finalizeAndReset(reason: "Session finished")
                }

            case .closed:
                if self.state == .stopping, self.mode == .realtime {
                    self.finalizeAndReset(reason: "Socket closed")
                } else if self.state == .listening, self.mode == .realtime {
                    self.tryReconnectRealtime(reason: "Realtime socket closed")
                }

            case .error(let msg):
                Console.line(msg)
                self.publishError(msg)
                if self.state == .listening, self.mode == .realtime {
                    self.tryReconnectRealtime(reason: "Realtime network error")
                }
            }
        }
    }

    private func finalizeAndReset(reason: String, overrideFinal: String? = nil) {
        guard state != .idle else { return }
        stopTimeoutWork?.cancel()
        stopTimeoutWork = nil
        autoStopWork?.cancel()
        autoStopWork = nil

        audio.stop()
        asr?.close()
        asr = nil
        fileAsr?.cancel()
        fileAsr = nil

        let isLectureRecording = statePublisher.lectureRecordingActive
        let rawFinal = (overrideFinal ?? transcript.finalTextAndClearUnstable()).trimmingCharacters(in: .whitespacesAndNewlines)
        var final_ = rawFinal
        if settings.secondPassCleanupEnabled && !settings.markdownModeEnabled && !isLectureRecording && !final_.isEmpty {
            final_ = TextPostProcessor.clean(final_)
        }
        Console.clearPartialLine()
        if final_.isEmpty {
            Console.line("Final text is empty")
        } else {
            clipboard.write(final_)
            Console.line("Final: \(final_)")
            Console.line("Copied to clipboard")
            DispatchQueue.main.async {
                self.statePublisher.toastMessage = "\u{5DF2}\u{590D}\u{5236}\u{5230}\u{526A}\u{8D34}\u{677F}"
            }
        }

        // v4: Add round to current session
        let shouldMarkdown = settings.markdownModeEnabled && !final_.isEmpty && !isLectureRecording
        if !final_.isEmpty, var session = currentSession {
            let round = TranscriptionRound(originalText: isLectureRecording ? rawFinal : final_)
            session.rounds.append(round)
            session.lectureOutputs = nil
            if !isLectureRecording { session.autoTitle() }
            // v6.0: record metadata
            let elapsed = Date().timeIntervalSince(recordStartedAt)
            if elapsed > 0 && elapsed < 600 {
                session.recordingDuration = (session.recordingDuration ?? 0) + elapsed
            }
            session.language = settings.language
            if isLectureRecording {
                let previousRaw = session.rawTranscript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let nextRaw: String
                if previousRaw.isEmpty {
                    nextRaw = rawFinal
                } else if rawFinal.isEmpty {
                    nextRaw = previousRaw
                } else {
                    nextRaw = previousRaw + "\n\n" + rawFinal
                }
                session.rawTranscript = nextRaw
                session.cleanTranscript = TextPostProcessor.cleanLectureTranscript(nextRaw)
            }
            sessionManager.updateSession(session)
            currentSession = session
            if shouldMarkdown {
                DispatchQueue.main.async {
                    self.statePublisher.currentSession = session
                    self.statePublisher.originalText = final_
                }
            }
            if isLectureRecording {
                let cleanText = session.lectureCleanText
                DispatchQueue.main.async {
                    self.statePublisher.currentSession = session
                    self.statePublisher.originalText = cleanText
                    self.statePublisher.markdownText = cleanText
                    self.statePublisher.editableText = cleanText
                }
            }
            Console.line("Session round \(session.rounds.count) added.")
        }

        let defaultLevel = MarkdownLevel(rawValue: settings.defaultMarkdownLevel) ?? .light

        resetToIdle(reason: reason, finalText: final_)

        if shouldMarkdown {
            DispatchQueue.main.async {
                self.statePublisher.markdownProcessing = true
                self.statePublisher.markdownText = ""
                self.statePublisher.markdownError = nil
                self.statePublisher.selectedTab = MarkdownTab(rawValue: defaultLevel.rawValue) ?? .light
            }
            startMarkdownForCurrentRound(level: defaultLevel)
        }
    }

    private func resetToIdle(reason: String, finalText: String) {
        state = .idle
        mode = nil
        recordedPCM.removeAll(keepingCapacity: false)
        fileStreamText = ""
        Console.line("State: IDLE (\(reason))")

        publishState(.idle)
        DispatchQueue.main.async {
            self.statePublisher.lastFinalText = finalText
            self.statePublisher.currentTranscript = ""
            self.statePublisher.remainingRecordSeconds = nil
            self.statePublisher.audioLevel = 0.0
            if !finalText.isEmpty {
                self.statePublisher.editableText = finalText
            }
            let shouldHideIndicator = self.settings.recordingIndicatorAutoHide && !self.settings.markdownModeEnabled
            if shouldHideIndicator {
                self.recordingIndicator?.hide()
            }
        }
    }

    // MARK: - v4 Markdown with levels

    private func startMarkdownForCurrentRound(level: MarkdownLevel) {
        guard let session = currentSession,
              let lastRound = session.rounds.last else { return }
        let sessionId = session.id

        DispatchQueue.main.async {
            self.statePublisher.generatingLevel = level
            if self.settings.llmMode == "dual" {
                self.statePublisher.glmProcessing = true
                self.statePublisher.glmText = ""
                self.statePublisher.glmGeneratingLevel = level
            }
        }

        // Build prompt
        let systemPrompt = MarkdownPrompts.systemPrompt(for: level)
        let userContent: String

        // Multi-round: if previous rounds exist, pass their markdown as context
        let roundIndex = session.rounds.count - 1
        if roundIndex > 0 {
            // Find previous round's same-level markdown for context
            let previousRounds = Array(session.rounds.prefix(roundIndex))
            let previousMarkdown = previousRounds.compactMap { $0.markdown[level.rawValue] }.joined(separator: "\n\n")
            if !previousMarkdown.isEmpty {
                userContent = MarkdownPrompts.continuationUserContent(for: level, previousMarkdown: previousMarkdown, newText: lastRound.originalText)
            } else {
                userContent = lastRound.originalText
            }
        } else {
            userContent = lastRound.originalText
        }

        startLLMServiceRequest(systemPrompt: systemPrompt, userContent: userContent, level: level, isFullRefinement: false, targetSessionId: sessionId)
    }

    func switchMarkdownLevel(_ level: MarkdownLevel) {
        guard let session = currentSession else { return }

        DispatchQueue.main.async {
            self.statePublisher.selectedTab = MarkdownTab(rawValue: level.rawValue) ?? .light
        }

        // When showing GLM version, check GLM cache first
        if statePublisher.showGLMVersion {
            let glmCombined = session.combinedGLMMarkdown(level: level)
            if !glmCombined.isEmpty {
                DispatchQueue.main.async {
                    self.statePublisher.markdownText = glmCombined
                }
                return
            }
            // No GLM cache, fall back to primary
        }

        // Check if we already have this level cached
        // First check fullRefinement, then per-round
        if let full = session.fullRefinement?[level.rawValue], !full.isEmpty {
            DispatchQueue.main.async {
                self.statePublisher.markdownText = full
            }
            return
        }

        let combined = session.combinedMarkdown(level: level)
        if !combined.isEmpty {
            DispatchQueue.main.async {
                self.statePublisher.markdownText = combined
            }
            return
        }

        // Not generated yet - generate on demand for all rounds
        llmService.cancelAll()
        DispatchQueue.main.async {
            self.statePublisher.markdownProcessing = true
            self.statePublisher.markdownText = ""
            self.statePublisher.markdownError = nil
        }

        // If only one round, generate for that round
        if session.rounds.count == 1 {
            startMarkdownForCurrentRound(level: level)
        } else {
            // Multiple rounds: do full refinement for this level
            triggerFullRefinement(level: level)
        }
    }

    func triggerFullRefinement(level: MarkdownLevel) {
        guard let session = currentSession, !session.rounds.isEmpty else { return }
        let sessionId = session.id

        llmService.cancelAll()
        DispatchQueue.main.async {
            self.statePublisher.markdownProcessing = true
            self.statePublisher.markdownText = ""
            self.statePublisher.markdownError = nil
            self.statePublisher.generatingLevel = level
            self.statePublisher.selectedTab = MarkdownTab(rawValue: level.rawValue) ?? .light
            if self.settings.llmMode == "dual" {
                self.statePublisher.glmProcessing = true
                self.statePublisher.glmText = ""
                self.statePublisher.glmGeneratingLevel = level
            }
        }

        let systemPrompt = MarkdownPrompts.systemPrompt(for: level)
        let userContent = MarkdownPrompts.fullRefinementUserContent(for: level, allText: session.allOriginalText)

        startLLMServiceRequest(systemPrompt: systemPrompt, userContent: userContent, level: level, isFullRefinement: true, targetSessionId: sessionId)
    }

    private func startLLMServiceRequest(systemPrompt: String, userContent: String, level: MarkdownLevel, isFullRefinement: Bool, targetSessionId: UUID) {
        llmService.startRequest(
            mode: settings.llmMode,
            settings: settings,
            systemPrompt: systemPrompt,
            userContent: userContent,
            onDelta: { [weak self] delta, type in
                DispatchQueue.main.async {
                    // Only update streaming text if we are still looking at the same session
                    guard self?.currentSession?.id == targetSessionId else { return }
                    
                    switch type {
                    case .primary:
                        self?.statePublisher.markdownText += delta
                    case .secondary:
                        self?.statePublisher.glmText += delta
                    }
                }
            },
            onComplete: { [weak self] result, type in
                self?.handleLLMCompletion(result: result, type: type, level: level, isFullRefinement: isFullRefinement, targetSessionId: targetSessionId)
            },
            onError: { [weak self] msg, type in
                DispatchQueue.main.async {
                    guard self?.currentSession?.id == targetSessionId else { return }
                    if type == .primary {
                        self?.statePublisher.markdownError = msg
                    } else {
                        Console.line("Secondary LLM error: \(msg)")
                    }
                }
            }
        )
    }

    private func handleLLMCompletion(result: String, type: LLMProviderType, level: MarkdownLevel, isFullRefinement: Bool, targetSessionId: UUID) {
        stateQueue.async {
            // Load the correct session, not just currentSession
            guard var session = self.sessionManager.session(for: targetSessionId) else { return }

            if type == .primary {
                if isFullRefinement {
                    if session.fullRefinement == nil { session.fullRefinement = [:] }
                    session.fullRefinement?[level.rawValue] = result
                } else {
                    let idx = session.rounds.count - 1
                    // Warning: Rounds might have changed if user edited? 
                    // For now assume append-only.
                    if idx >= 0 {
                        session.rounds[idx].markdown[level.rawValue] = result
                    }
                }
            } else {
                // Secondary (GLM in dual mode)
                if isFullRefinement {
                    if session.glmFullRefinement == nil { session.glmFullRefinement = [:] }
                    session.glmFullRefinement?[level.rawValue] = result
                } else {
                    let idx = session.rounds.count - 1
                    if idx >= 0 {
                        session.rounds[idx].glmMarkdown[level.rawValue] = result
                    }
                }
            }

            self.sessionManager.updateSession(session)
            
            // Only update UI if we are still on this session
            if self.currentSession?.id == targetSessionId {
                self.currentSession = session
                DispatchQueue.main.async {
                    self.statePublisher.currentSession = session
                    
                    if type == .primary {
                        self.statePublisher.markdownProcessing = false
                        self.statePublisher.generatingLevel = nil
                        if !result.isEmpty {
                            self.clipboard.write(result, asMarkdown: true)
                            Console.line("Markdown (\(level.displayName)) rich-copied to clipboard")
                            self.statePublisher.toastMessage = "\u{5DF2}\u{590D}\u{5236}\u{5230}\u{526A}\u{8D34}\u{677F}"
                        }
                    } else {
                        self.statePublisher.glmProcessing = false
                        self.statePublisher.glmGeneratingLevel = nil
                        self.statePublisher.toastMessage = "GLM \u{6DF1}\u{5EA6}\u{7248}\u{672C}\u{5DF2}\u{5C31}\u{7EEA}"
                    }
                }
            } else {
                 Console.line("Background LLM task finished for session \(targetSessionId)")
            }
        }
    }

    func continueRecording(mode: CaptureMode) {
        stateQueue.async {
            guard self.state == .idle else { return }
            guard self.currentSession != nil else { return }
            Console.line("Continuing recording in current session...")
            self.beginListening(mode: mode)
        }
    }

    func saveToObsidian() {
        guard let session = currentSession else { return }
        let vaultPath = settings.obsidianVaultPath
        guard !vaultPath.isEmpty else {
            publishError("\u{8BF7}\u{5148}\u{5728}\u{8BBE}\u{7F6E}\u{4E2D}\u{914D}\u{7F6E} Obsidian Vault \u{8DEF}\u{5F84}")
            return
        }

        let fm = FileManager.default
        guard fm.isDirectory(atPath: vaultPath) else {
            publishError("Obsidian Vault \u{8DEF}\u{5F84}\u{4E0D}\u{5B58}\u{5728}: \(vaultPath)")
            return
        }

        let content: String
        if session.kind == .lecture {
            if statePublisher.lectureNoteMode == .transcript {
                content = session.lectureCleanText
            } else {
                content = session.lectureOutputs?[statePublisher.lectureNoteMode.rawValue] ?? ""
            }
        } else if let level = statePublisher.selectedTab.markdownLevel {
            if statePublisher.showGLMVersion {
                content = session.combinedGLMMarkdown(level: level)
            } else {
                content = session.combinedMarkdown(level: level)
            }
        } else {
            content = session.allOriginalText
        }
        guard !content.isEmpty else {
            publishError("\u{6CA1}\u{6709}\u{53EF}\u{4FDD}\u{5B58}\u{7684}\u{5185}\u{5BB9}")
            return
        }

        let dateStr = {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd_HHmmss"
            return f.string(from: session.createdAt)
        }()
        let safeTitle = session.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let fileName: String
        if let existing = session.obsidianFilePath {
            fileName = (existing as NSString).lastPathComponent
        } else {
            fileName = "FlashASR_\(dateStr)_\(safeTitle).md"
        }

        let filePath = (vaultPath as NSString).appendingPathComponent(fileName)
        do {
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            Console.line("Saved to Obsidian: \(filePath)")

            // Update session with file path
            if var updated = currentSession {
                updated.obsidianFilePath = fileName
                sessionManager.updateSession(updated)
                currentSession = updated
                DispatchQueue.main.async {
                    self.statePublisher.currentSession = updated
                    self.statePublisher.toastMessage = "\u{5DF2}\u{4FDD}\u{5B58}\u{5230} Obsidian"
                }
            }
        } catch {
            publishError("Obsidian \u{4FDD}\u{5B58}\u{5931}\u{8D25}: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.statePublisher.toastMessage = "\u{4FDD}\u{5B58}\u{5931}\u{8D25}: \(error.localizedDescription)"
            }
        }
    }

    func exportSession(format: ExportFormat) {
        guard let session = currentSession else { return }
        let content: String
        if session.kind == .lecture {
            if statePublisher.lectureNoteMode == .transcript {
                content = session.lectureCleanText
            } else {
                content = session.lectureOutputs?[statePublisher.lectureNoteMode.rawValue] ?? ""
            }
        } else if let level = statePublisher.selectedTab.markdownLevel {
            content = statePublisher.showGLMVersion
                ? session.combinedGLMMarkdown(level: level)
                : session.combinedMarkdown(level: level)
        } else {
            content = session.allOriginalText
        }
        guard !content.isEmpty else {
            DispatchQueue.main.async {
                self.statePublisher.toastMessage = "\u{6CA1}\u{6709}\u{53EF}\u{5BFC}\u{51FA}\u{7684}\u{5185}\u{5BB9}"
            }
            return
        }

        let metadata = ExportMetadata(
            title: session.displayTitle,
            date: session.createdAt,
            wordCount: session.wordCount,
            duration: session.recordingDuration,
            tags: session.tags,
            language: session.language,
            roundCount: session.rounds.count
        )

        let panel = NSSavePanel()
        let dateStr: String = {
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmm"; return f.string(from: session.createdAt)
        }()
        let safeTitle: String = {
            if session.kind == .lecture {
                let base = [session.courseName, session.chapter, statePublisher.lectureNoteMode.displayName]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "_")
                if !base.isEmpty {
                    return base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                }
            }
            let plain = session.title.isEmpty ? "session" : session.title
            return plain.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        }()
        panel.nameFieldStringValue = "FlashASR_\(dateStr)_\(safeTitle).\(format.fileExtension)"
        panel.allowedContentTypes = [.data]

        if panel.runModal() == .OK, let url = panel.url {
            let exported = MarkdownExporter.export(markdown: content, format: format, metadata: metadata)
            do {
                try exported.write(to: url, atomically: true, encoding: .utf8)
                Console.line("Exported \(format.rawValue) to: \(url.path)")
                DispatchQueue.main.async {
                    self.statePublisher.toastMessage = "\u{5DF2}\u{5BFC}\u{51FA} \(format.displayName)"
                }
            } catch {
                DispatchQueue.main.async {
                    self.statePublisher.toastMessage = "\u{5BFC}\u{51FA}\u{5931}\u{8D25}: \(error.localizedDescription)"
                }
            }
        }
    }

    func renameSession(_ id: UUID, title: String) {
        guard var session = sessionManager.session(for: id) else { return }
        session.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        sessionManager.updateSession(session)
        if currentSession?.id == id {
            currentSession = session
            DispatchQueue.main.async {
                self.statePublisher.currentSession = session
            }
        }
    }

    func loadSession(_ id: UUID) {
        guard let session = sessionManager.session(for: id) else { return }
        currentSession = session
        let defaultLevel = MarkdownLevel(rawValue: settings.defaultMarkdownLevel) ?? .light
        let markdown = session.combinedMarkdown(level: defaultLevel)
        DispatchQueue.main.async {
            let baseText = session.kind == .lecture ? session.lectureCleanText : session.allOriginalText
            self.statePublisher.currentSession = session
            self.statePublisher.lectureNoteMode = .transcript
            self.statePublisher.originalText = baseText
            self.statePublisher.markdownText = markdown
            self.statePublisher.selectedTab = markdown.isEmpty ? .original : (MarkdownTab(rawValue: defaultLevel.rawValue) ?? .light)
            self.statePublisher.markdownProcessing = false
            self.statePublisher.markdownError = nil
            self.statePublisher.editableText = baseText
            self.recordingIndicator?.show(state: self.statePublisher)
        }
        Console.line("Loaded session: \(session.title) (\(session.rounds.count) rounds)")
    }

    func deleteSession(_ id: UUID) {
        if state != .idle {
            DispatchQueue.main.async {
                self.statePublisher.toastMessage = "\u{8FDB}\u{7A0B}\u{4E2D}\u{65E0}\u{6CD5}\u{5220}\u{9664}\u{4F1A}\u{8BDD}"
            }
            return
        }
        sessionManager.deleteSession(id: id)
        if currentSession?.id == id {
            closeSession()
        } else if statePublisher.currentSession?.id == id {
            DispatchQueue.main.async {
                self.statePublisher.currentSession = nil
            }
        }
    }

    func toggleGLMVersion() {
        guard let session = currentSession else { return }
        let newValue = !statePublisher.showGLMVersion

        DispatchQueue.main.async {
            self.statePublisher.showGLMVersion = newValue
        }

        // Refresh displayed text for current tab
        guard let level = statePublisher.selectedTab.markdownLevel else { return }

        if newValue {
            // Switching to GLM: try to show GLM content
            let glmContent = session.combinedGLMMarkdown(level: level)
            if !glmContent.isEmpty {
                DispatchQueue.main.async {
                    self.statePublisher.markdownText = glmContent
                }
            } else if statePublisher.glmProcessing {
                // GLM still processing, show streaming text
                DispatchQueue.main.async {
                    self.statePublisher.markdownText = self.statePublisher.glmText
                }
            }
            // else: keep current text (MiMo), user sees no GLM content yet
        } else {
            // Switching back to MiMo/primary
            let content = session.combinedMarkdown(level: level)
            if !content.isEmpty {
                DispatchQueue.main.async {
                    self.statePublisher.markdownText = content
                }
            }
        }
    }

    func closeSession() {
        llmService.cancelAll()
        lectureController.lectureImportService.cancel()
        currentSession = nil
        DispatchQueue.main.async {
            self.statePublisher.currentSession = nil
            self.statePublisher.markdownProcessing = false
            self.statePublisher.markdownText = ""
            self.statePublisher.originalText = ""
            self.statePublisher.markdownError = nil
            self.statePublisher.generatingLevel = nil
            self.statePublisher.selectedTab = .original
            self.statePublisher.glmProcessing = false
            self.statePublisher.glmText = ""
            self.statePublisher.showGLMVersion = false
            self.statePublisher.glmGeneratingLevel = nil
            self.statePublisher.editableText = ""
            self.statePublisher.canUndoTransform = false
            self.statePublisher.lectureNoteMode = .transcript
            self.statePublisher.lectureRecordingActive = false
            self.statePublisher.activeLectureSessionId = nil
            self.statePublisher.importProgress = 0
            self.statePublisher.importStageText = ""
            self.statePublisher.failedLectureSegments = []
            self.statePublisher.lectureTotalSegments = 0
            self.recordingIndicator?.hide()
        }
    }

    func cancelMarkdown() {
        llmService.cancelAll()
        DispatchQueue.main.async {
            self.statePublisher.markdownProcessing = false
            self.statePublisher.generatingLevel = nil
            self.statePublisher.glmProcessing = false
            self.statePublisher.glmGeneratingLevel = nil
        }
    }

    // Keep v3 compat
    func closeMarkdownPanel() {
        closeSession()
    }

    // MARK: - v4.1 Text upload

    func processClipboardText() {
        let pb = NSPasteboard.general
        guard let text = pb.string(forType: .string), !text.isEmpty else {
            publishError("\u{526A}\u{8D34}\u{677F}\u{4E2D}\u{6CA1}\u{6709}\u{6587}\u{672C}")
            return
        }
        processUploadedText(text)
    }

    func processFileText() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [UTType.plainText]
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.message = "\u{9009}\u{62E9}\u{6587}\u{672C}\u{6587}\u{4EF6}\u{8FDB}\u{884C} Markdown \u{6574}\u{7406}"
            if panel.runModal() == .OK, let url = panel.url {
                do {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    guard !text.isEmpty else {
                        self.publishError("\u{6587}\u{4EF6}\u{5185}\u{5BB9}\u{4E3A}\u{7A7A}")
                        return
                    }
                    self.processUploadedText(text)
                } catch {
                    self.publishError("\u{8BFB}\u{53D6}\u{6587}\u{4EF6}\u{5931}\u{8D25}: \(error.localizedDescription)")
                }
            }
        }
    }

    func processUploadedText(_ text: String, level: MarkdownLevel? = nil) {
        stateQueue.async {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                self.publishError("\u{6587}\u{672C}\u{4E3A}\u{7A7A}\u{FF0C}\u{65E0}\u{6CD5}\u{8FDB}\u{884C}\u{6574}\u{7406}")
                return
            }

            // Close any existing session first
            self.llmService.cancelAll()

            var session = TranscriptionSession()
            let round = TranscriptionRound(originalText: trimmed)
            session.rounds.append(round)
            session.autoTitle()
            self.sessionManager.updateSession(session)
            self.currentSession = session

            let targetLevel = level ?? MarkdownLevel(rawValue: self.settings.defaultMarkdownLevel) ?? .light
            DispatchQueue.main.async {
                self.statePublisher.currentSession = session
                self.statePublisher.originalText = trimmed
                self.statePublisher.markdownProcessing = true
                self.statePublisher.markdownText = ""
                self.statePublisher.markdownError = nil
                self.statePublisher.selectedTab = MarkdownTab(rawValue: targetLevel.rawValue) ?? .light
                self.statePublisher.editableText = trimmed
                self.recordingIndicator?.show(state: self.statePublisher)
            }
            self.startMarkdownForCurrentRound(level: targetLevel)
        }
    }

    func startTransformFromEditableText(level: MarkdownLevel? = nil) {
        let current = statePublisher.editableText
        let existing = currentSession?.allOriginalText ?? statePublisher.originalText
        let previous = current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? existing : current
        lastTransformUndoText = previous
        lastTransformUndoSession = currentSession
        DispatchQueue.main.async {
            self.statePublisher.canUndoTransform = !previous.isEmpty
        }
        processUploadedText(current, level: level)
    }

    func undoLastTransform() {
        guard let prev = lastTransformUndoText, !prev.isEmpty else { return }
        let prevSession = lastTransformUndoSession
        lastTransformUndoText = nil
        lastTransformUndoSession = nil
        llmService.cancelAll()
        currentSession = prevSession
        DispatchQueue.main.async {
            self.statePublisher.canUndoTransform = false
            self.statePublisher.editableText = prev
            self.statePublisher.currentSession = prevSession
            self.statePublisher.selectedTab = .original
            self.statePublisher.markdownProcessing = false
            self.statePublisher.markdownText = ""
            self.statePublisher.generatingLevel = nil
            self.statePublisher.glmProcessing = false
            self.statePublisher.glmText = ""
            self.statePublisher.glmGeneratingLevel = nil
            self.statePublisher.toastMessage = "\u{5DF2}\u{64A4}\u{56DE}"
        }
    }

    private func startPermissionTimer() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshPermissions(startup: false)
        }
    }

    func refreshPermissions(startup: Bool) {
        let snap = PermissionService.snapshot()
        permissionSnapshot = snap
        let effectiveReady = snap.allGranted || settings.permissionTrustOverride

        DispatchQueue.main.async {
            self.statePublisher.permissions = snap
            self.statePublisher.serviceReady = effectiveReady
            self.statePublisher.hotkeyConflictRealtime = HotkeyConflictService.hasConflict(
                keyCode: self.settings.realtimeHotkeyCode,
                modifiers: self.settings.realtimeHotkeyModifiers
            )
            self.statePublisher.hotkeyConflictFile = HotkeyConflictService.hasConflict(
                keyCode: self.settings.fileHotkeyCode,
                modifiers: self.settings.fileHotkeyModifiers
            )
            self.onPermissionChanged?(snap)
        }

        if effectiveReady {
            publishError(nil)
            if !keyTapActive {
                if keyTap.start() {
                    keyTapActive = true
                    Console.line("Global hotkey listener enabled.")
                } else {
                    Console.line("Global key event tap unavailable. Enable FlashASR in Privacy & Security -> Accessibility and Input Monitoring.")
                    publishError("Global key event tap unavailable. Check Accessibility/Input Monitoring.")
                }
            }
            return
        }

        if keyTapActive {
            keyTap.stop()
            keyTapActive = false
            Console.line("Hotkey listener disabled until all permissions are granted.")
        }
        if startup {
            publishError("Permissions required: Microphone, Accessibility, Input Monitoring.")
        }
    }

    private func tryReconnectRealtime(reason: String) {
        guard state == .listening, mode == .realtime else { return }
        guard reconnectAttempts < maxReconnectAttempts else {
            beginStopping(reason: "\(reason); reconnect failed")
            return
        }
        reconnectAttempts += 1
        let wait = Double(reconnectAttempts)
        Console.line("Network unstable. Reconnecting realtime ASR (\(reconnectAttempts)/\(maxReconnectAttempts))...")
        publishError("Network unstable. Trying reconnect \(reconnectAttempts)/\(maxReconnectAttempts).")
        asr?.close()
        asr = nil
        reconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == .listening, self.mode == .realtime else { return }
            guard let wsURL = URL(string: self.settings.wsBaseURL) else { return }
            let client = ASRWebSocketClient(
                apiKey: self.settings.effectiveDashscopeAPIKey,
                url: wsURL,
                model: self.settings.model,
                language: self.settings.language
            )
            self.asr = client
            client.onEvent = { [weak self] event in
                self?.handleASREvent(event)
            }
            client.connect()
        }
        reconnectWork = work
        stateQueue.asyncAfter(deadline: .now() + wait, execute: work)
    }

    private func retryLastFailedFileUpload() {
        stateQueue.async {
            guard self.state == .idle else { return }
            let apiKey = self.settings.effectiveDashscopeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                self.publishError("Dashscope API Key is empty. Please configure it in Settings -> API Keys.")
                return
            }
            guard let url = self.lastFailedFileAudioURL,
                  let wav = try? Data(contentsOf: url),
                  !wav.isEmpty,
                  let endpoint = URL(string: self.settings.fileASRURL)
            else {
                self.publishError("No failed file upload to retry.")
                return
            }

            self.mode = .fileFlash
            self.state = .stopping
            self.fileStreamText = ""
            self.publishState(.stopping, mode: .fileFlash)
            Console.line("Retrying last failed file upload...")
            let client = FileASRStreamClient(
                apiKey: apiKey,
                endpoint: endpoint,
                model: self.settings.fileModel,
                language: self.settings.language
            )
            self.fileAsr = client
            client.onDelta = { [weak self] delta in
                self?.stateQueue.async {
                    guard let self else { return }
                    self.fileStreamText += delta
                    Console.partial(self.fileStreamText)
                    self.typer.apply(text: self.fileStreamText)
                    self.publishTranscript(self.fileStreamText)
                }
            }
            client.onError = { [weak self] msg in
                self?.publishError(msg)
            }
            client.onDone = { [weak self] in
                self?.stateQueue.async {
                    guard let self else { return }
                    if !self.fileStreamText.isEmpty {
                        self.lastFailedFileAudioURL = nil
                    }
                    self.finalizeAndReset(reason: "Retry upload finished", overrideFinal: self.fileStreamText)
                }
            }
            client.start(base64Wav: wav.base64EncodedString())
        }
    }

    deinit {
        permissionTimer?.invalidate()
        permissionTimer = nil
        if keyTapActive {
            keyTap.stop()
            keyTapActive = false
        }
        reconnectWork?.cancel()
        reconnectWork = nil
        partialStabilizeWork?.cancel()
        partialStabilizeWork = nil
        llmService.cancelAll()
        lectureController.lectureImportService.cancel()
    }
}

// MARK: - FileManager helper
private extension FileManager {
    func isDirectory(atPath path: String) -> Bool {
        var isDir: ObjCBool = false
        return fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
