import Foundation
import AVFoundation
import AppKit

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

    var recordingIndicator: RecordingIndicatorController?

    private lazy var keyTap = GlobalKeyTap(settings: settings) { [weak self] action in
        self?.handleTrigger(action)
    }

    init(settings: SettingsManager, statePublisher: AppStatePublisher) {
        self.settings = settings
        self.statePublisher = statePublisher
    }

    func start() {
        Console.line("FlashASR started.")
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
    }

    func handleTrigger(_ action: TriggerAction) {
        stateQueue.async {
            guard self.permissionSnapshot.allGranted else {
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
        guard permissionSnapshot.allGranted else {
            publishError("Permissions not ready. Please grant Microphone, Accessibility, and Input Monitoring.")
            return
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
        typer.prepareForSession(realtimeTypeEnabled: settings.realtimeTypeEnabled)
        stopTimeoutWork?.cancel()
        stopTimeoutWork = nil
        autoStopWork?.cancel()
        autoStopWork = nil

        publishState(.listening, mode: mode)
        publishTranscript("")
        DispatchQueue.main.async {
            self.statePublisher.remainingRecordSeconds = mode == .fileFlash ? 300 : nil
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
                    apiKey: self.settings.apiKey,
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
            apiKey: settings.apiKey,
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

        var final_ = (overrideFinal ?? transcript.finalTextAndClearUnstable()).trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.secondPassCleanupEnabled, !final_.isEmpty {
            final_ = TextPostProcessor.clean(final_)
        }
        Console.clearPartialLine()
        if final_.isEmpty {
            Console.line("Final text is empty")
        } else {
            clipboard.write(final_)
            Console.line("Final: \(final_)")
            Console.line("Copied to clipboard")
        }

        state = .idle
        mode = nil
        recordedPCM.removeAll(keepingCapacity: false)
        fileStreamText = ""
        Console.line("State: IDLE (\(reason))")

        publishState(.idle)
        DispatchQueue.main.async {
            self.statePublisher.lastFinalText = final_
            self.statePublisher.currentTranscript = ""
            self.statePublisher.remainingRecordSeconds = nil
            if self.settings.recordingIndicatorAutoHide {
                self.recordingIndicator?.hide()
            }
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

        DispatchQueue.main.async {
            self.statePublisher.permissions = snap
            self.statePublisher.serviceReady = snap.allGranted
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

        if snap.allGranted {
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
                apiKey: self.settings.apiKey,
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
                apiKey: self.settings.apiKey,
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
    }
}
