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

        if keyTap.start() {
            Console.line("Global hotkey listener enabled.")
        } else {
            Console.line("Global key event tap unavailable. Enable FlashASR in Privacy & Security -> Accessibility and Input Monitoring.")
        }

        // Listen for menu-triggered actions
        NotificationCenter.default.addObserver(forName: .triggerRealtime, object: nil, queue: .main) { [weak self] _ in
            self?.handleTrigger(.realtimeToggle)
        }
        NotificationCenter.default.addObserver(forName: .triggerFile, object: nil, queue: .main) { [weak self] _ in
            self?.handleTrigger(.fileToggle)
        }
    }

    func handleTrigger(_ action: TriggerAction) {
        stateQueue.async {
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

    private func publishError(_ msg: String) {
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
        self.mode = mode
        state = .listening
        transcript.reset()
        fileStreamText = ""
        recordedPCM.removeAll(keepingCapacity: true)
        recordStartedAt = Date()
        typer.prepareForSession(realtimeTypeEnabled: settings.realtimeTypeEnabled)
        stopTimeoutWork?.cancel()
        stopTimeoutWork = nil
        autoStopWork?.cancel()
        autoStopWork = nil

        publishState(.listening, mode: mode)
        publishTranscript("")

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

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        Console.line("Microphone auth status: \(status.rawValue)")

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

        switch status {
        case .authorized:
            continueStart()
        case .notDetermined:
            Console.line("Requesting microphone permission...")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard let self else { return }
                self.stateQueue.async {
                    guard self.state == .listening else { return }
                    Console.line("Microphone permission result: \(granted)")
                    guard granted else {
                        Console.line("Microphone permission denied")
                        self.state = .idle
                        self.mode = nil
                        self.publishState(.idle)
                        return
                    }
                    continueStart()
                }
            }
        case .denied, .restricted:
            Console.line("Microphone permission denied/restricted. Enable in: System Settings -> Privacy & Security -> Microphone")
            state = .idle
            self.mode = nil
            publishState(.idle)
            publishError("Microphone permission denied. Please enable in System Settings.")
        @unknown default:
            Console.line("Unknown microphone auth status")
            state = .idle
            self.mode = nil
            publishState(.idle)
        }
    }

    private func handleFileFrame(_ frame: Data) {
        stateQueue.async {
            guard self.state == .listening, self.mode == .fileFlash else { return }
            self.recordedPCM.append(frame)
            let elapsed = Date().timeIntervalSince(self.recordStartedAt)
            let maxSeconds = 300.0
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
                self.transcript.handlePartial(text) { merged in
                    Console.partial(merged)
                    self.typer.apply(text: merged)
                    self.publishTranscript(merged)
                }

            case .final(let text):
                guard (self.state == .listening || self.state == .stopping), self.mode == .realtime else { return }
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
                    self.beginStopping(reason: "Socket closed while listening")
                }

            case .error(let msg):
                Console.line(msg)
                self.publishError(msg)
                if self.state == .listening, self.mode == .realtime {
                    self.beginStopping(reason: "ASR error")
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

        let final_ = (overrideFinal ?? transcript.finalTextAndClearUnstable()).trimmingCharacters(in: .whitespacesAndNewlines)
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
            self.recordingIndicator?.hide()
        }
    }

    deinit {
        keyTap.stop()
    }
}
