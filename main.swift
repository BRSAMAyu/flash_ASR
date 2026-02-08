import Foundation
import AVFoundation
import AppKit
import Carbon

// Build:
// swiftc /Users/a/code/ASR/flash_ASR/main.swift -framework AVFoundation -framework Carbon -framework AppKit -o /Users/a/code/ASR/flash_ASR/flash_asr
// Run:
// ./flash_asr

private let API_KEY = "sk-82f726c10954417187fa35d39630fd7c"
private let WS_BASE_URL = "wss://dashscope.aliyuncs.com/api-ws/v1/realtime"
private let MODEL = "qwen3-asr-flash-realtime"
private let LANGUAGE = "zh"

private let SAMPLE_RATE: Double = 16_000
private let CHANNELS: AVAudioChannelCount = 1
private let FRAME_MS = 20
private let FRAME_BYTES = Int(SAMPLE_RATE * Double(FRAME_MS) / 1000.0) * MemoryLayout<Int16>.size

private let SILENCE_THRESHOLD: Int32 = 220
private let PARTIAL_PRINT_THROTTLE: TimeInterval = 0.15
private let STOP_FINALIZE_TIMEOUT: TimeInterval = 2.0

enum AppState {
    case idle
    case listening
    case stopping
}

private final class Console {
    private static let queue = DispatchQueue(label: "console.queue")
    private static var lastLen = 0

    static func line(_ text: String) {
        queue.async {
            fputs("\r", stdout)
            fputs(String(repeating: " ", count: max(0, lastLen)).appending("\r"), stdout)
            print(text)
            fflush(stdout)
            lastLen = 0
        }
    }

    static func partial(_ text: String) {
        queue.async {
            let pad = max(0, lastLen - text.count)
            fputs("\r\(text)\(String(repeating: " ", count: pad))", stdout)
            fflush(stdout)
            lastLen = text.count
        }
    }

    static func clearPartialLine() {
        queue.async {
            fputs("\r\(String(repeating: " ", count: max(0, lastLen)))\r", stdout)
            fflush(stdout)
            lastLen = 0
        }
    }
}

private final class TranscriptBuffer {
    private let queue = DispatchQueue(label: "transcript.queue")
    private var stableText = ""
    private var unstableText = ""
    private var lastRender = Date.distantPast

    func reset() {
        queue.sync {
            stableText = ""
            unstableText = ""
            lastRender = .distantPast
        }
    }

    func handlePartial(_ text: String, render: @escaping (String) -> Void) {
        queue.async {
            self.unstableText = text
            let now = Date()
            guard now.timeIntervalSince(self.lastRender) >= PARTIAL_PRINT_THROTTLE else { return }
            self.lastRender = now
            render(self.combinedTextLocked())
        }
    }

    func handleFinal(_ text: String, render: @escaping (String) -> Void) {
        queue.async {
            if !self.stableText.isEmpty, !self.stableText.hasSuffix(" "), !text.hasPrefix(" ") {
                self.stableText += " "
            }
            self.stableText += text
            self.unstableText = ""
            self.lastRender = Date()
            render(self.combinedTextLocked())
        }
    }

    func finalTextAndClearUnstable() -> String {
        queue.sync {
            if !unstableText.isEmpty {
                if !stableText.isEmpty, !stableText.hasSuffix(" "), !unstableText.hasPrefix(" ") {
                    stableText += " "
                }
                stableText += unstableText
                unstableText = ""
            }
            return stableText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func combinedTextLocked() -> String {
        if stableText.isEmpty { return unstableText }
        if unstableText.isEmpty { return stableText }
        if unstableText.hasPrefix(" ") || stableText.hasSuffix(" ") {
            return stableText + unstableText
        }
        return stableText + " " + unstableText
    }
}

private enum ASREvent {
    case partial(String)
    case final(String)
    case transcriptionFailed(String)
    case sessionFinished
    case opened
    case closed
    case error(String)
}

private final class ASRWebSocketClient: NSObject, URLSessionWebSocketDelegate {
    private let apiKey: String
    private let url: URL
    private let model: String
    private let language: String

    private let sendQueue = DispatchQueue(label: "asr.send.queue")
    private let eventQueue = DispatchQueue(label: "asr.event.queue")

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var connected = false
    private var closed = false

    var onEvent: ((ASREvent) -> Void)?

    init(apiKey: String, url: URL, model: String, language: String) {
        self.apiKey = apiKey
        self.url = url
        self.model = model
        self.language = language
    }

    func connect() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "model", value: model)]
        guard let resolvedURL = comps?.url else {
            dispatch(.error("Invalid WebSocket URL"))
            return
        }

        var request = URLRequest(url: resolvedURL)
        request.timeoutInterval = 30
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let wsTask = session!.webSocketTask(with: request)
        task = wsTask
        wsTask.resume()
        receiveLoop()
    }

    func sendAudioFrame(_ frame: Data) {
        sendQueue.async {
            guard self.connected, !self.closed, let task = self.task else { return }
            let payload: [String: Any] = [
                "event_id": self.eventID(),
                "type": "input_audio_buffer.append",
                "audio": frame.base64EncodedString()
            ]
            self.sendJSON(payload, task: task)
        }
    }

    func endSession() {
        sendQueue.async {
            guard !self.closed, let task = self.task else { return }
            self.sendJSON([
                "event_id": self.eventID(),
                "type": "session.finish"
            ], task: task)
        }
    }

    func close() {
        sendQueue.async {
            guard !self.closed else { return }
            self.closed = true
            self.connected = false
            self.task?.cancel(with: .normalClosure, reason: nil)
            self.session?.invalidateAndCancel()
            self.task = nil
            self.session = nil
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.dispatch(.error("WebSocket receive failed: \(error.localizedDescription)"))
                self.dispatch(.closed)
            case .success(let message):
                self.handleMessage(message)
                if !self.closed {
                    self.receiveLoop()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let str):
            text = str
        case .data(let data):
            text = String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            return
        }

        guard !text.isEmpty,
              let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return }

        switch type {
        case "session.created":
            sendSessionUpdateIfNeeded()
        case "conversation.item.input_audio_transcription.text":
            let stable = (obj["text"] as? String) ?? ""
            let stash = (obj["stash"] as? String) ?? ""
            let merged = stable + stash
            if !merged.isEmpty {
                dispatch(.partial(merged))
            }
        case "conversation.item.input_audio_transcription.completed":
            if let f = firstString(in: obj, keys: ["transcript", "text", "stash"]), !f.isEmpty {
                dispatch(.final(f))
            }
        case "conversation.item.input_audio_transcription.failed":
            let msg = firstString(in: obj, keys: ["message", "error", "detail"]) ?? "transcription failed"
            dispatch(.transcriptionFailed(msg))
        case "session.finished", "response.done", "conversation.done":
            dispatch(.sessionFinished)
        case "error":
            let msg = firstString(in: obj, keys: ["message", "error", "detail"]) ?? "unknown error"
            dispatch(.error("ASR server error: \(msg)"))
        default:
            break
        }
    }

    private func sendSessionUpdateIfNeeded() {
        sendQueue.async {
            guard self.connected, !self.closed, let task = self.task else { return }
            let payload: [String: Any] = [
                "event_id": self.eventID(),
                "type": "session.update",
                "session": [
                    "modalities": ["text"],
                    "input_audio_format": "pcm",
                    "sample_rate": Int(SAMPLE_RATE),
                    "input_audio_transcription": [
                        "language": self.language
                    ],
                    "turn_detection": [
                        "type": "server_vad",
                        "threshold": 0.0,
                        "silence_duration_ms": 400
                    ]
                ]
            ]
            self.sendJSON(payload, task: task)
        }
    }

    private func sendJSON(_ object: [String: Any], task: URLSessionWebSocketTask) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else {
            dispatch(.error("JSON encode failed"))
            return
        }

        task.send(.string(text)) { [weak self] error in
            if let error {
                self?.dispatch(.error("WebSocket send failed: \(error.localizedDescription)"))
            }
        }
    }

    private func dispatch(_ event: ASREvent) {
        eventQueue.async { [weak self] in
            self?.onEvent?(event)
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        connected = true
        dispatch(.opened)
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        connected = false
        dispatch(.closed)
    }

    private func firstString(in obj: Any, keys: [String]) -> String? {
        if let dict = obj as? [String: Any] {
            for key in keys {
                if let str = dict[key] as? String { return str }
            }
            for value in dict.values {
                if let found = firstString(in: value, keys: keys) { return found }
            }
        } else if let arr = obj as? [Any] {
            for item in arr {
                if let found = firstString(in: item, keys: keys) { return found }
            }
        }
        return nil
    }

    private func eventID() -> String {
        "event_\(Int(Date().timeIntervalSince1970 * 1000))_\(Int.random(in: 1000...9999))"
    }
}

private final class AudioCapture {
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "audio.capture.queue", qos: .userInitiated)

    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var pending = Data()
    private var running = false
    private var frameHandler: ((Data) -> Void)?

    func start(frameHandler: @escaping (Data) -> Void) throws {
        guard !running else { return }
        running = true
        self.frameHandler = frameHandler
        pending.removeAll(keepingCapacity: true)

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: SAMPLE_RATE,
                                         channels: CHANNELS,
                                         interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: target)
        else {
            running = false
            throw NSError(domain: "AudioCapture", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio format init failed"])
        }

        self.converter = converter
        self.targetFormat = target

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 256, format: inputFormat) { [weak self] buffer, _ in
            self?.queue.async {
                self?.process(buffer: buffer)
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        targetFormat = nil
        pending.removeAll(keepingCapacity: false)
        frameHandler = nil
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard running,
              let converter,
              let targetFormat,
              let frameHandler
        else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return }

        var error: NSError?
        var fed = false
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil else { return }
        guard status == .haveData, out.frameLength > 0 else { return }
        guard let ch = out.int16ChannelData else { return }

        let count = Int(out.frameLength)
        let data = Data(bytes: ch[0], count: count * MemoryLayout<Int16>.size)
        pending.append(data)

        while pending.count >= FRAME_BYTES {
            let frame = pending.prefix(FRAME_BYTES)
            pending.removeFirst(FRAME_BYTES)
            let frameData = Data(frame)
            if isVoice(frameData) {
                frameHandler(frameData)
            }
        }
    }

    private func isVoice(_ frame: Data) -> Bool {
        return frame.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            if samples.isEmpty { return false }
            var peak: Int32 = 0
            var i = 0
            while i < samples.count {
                let s = Int32(samples[i])
                let v = s >= 0 ? s : -s
                if v > peak { peak = v }
                if peak >= SILENCE_THRESHOLD { return true }
                i += 4
            }
            return false
        }
    }
}

private final class ClipboardWriter {
    func write(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

private final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPress: () -> Void

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
    }

    func start() throws {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let me = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                me.onPress()
                return noErr
            },
            1,
            &spec,
            userData,
            &handlerRef
        )

        guard installStatus == noErr else {
            throw NSError(domain: "Hotkey", code: Int(installStatus), userInfo: [NSLocalizedDescriptionKey: "InstallEventHandler failed: \(installStatus)"])
        }

        let sig = OSType(0x46534152) // 'FSAR'
        let hotKeyID = EventHotKeyID(signature: sig, id: 1)
        // Carbon does not reliably expose left/right modifier separation for hotkeys.
        // This registers Option+Space globally; user can press Right Option + Space.
        let mods = UInt32(optionKey)

        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            mods,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            throw NSError(domain: "Hotkey", code: Int(registerStatus), userInfo: [NSLocalizedDescriptionKey: "RegisterEventHotKey failed: \(registerStatus)"])
        }
    }

    func stop() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = handlerRef {
            RemoveEventHandler(handler)
            handlerRef = nil
        }
    }
}

private final class AppController {
    private let stateQueue = DispatchQueue(label: "app.state.queue")

    private var state: AppState = .idle
    private var audio = AudioCapture()
    private var asr: ASRWebSocketClient?
    private let transcript = TranscriptBuffer()
    private let clipboard = ClipboardWriter()
    private var stopTimeoutWork: DispatchWorkItem?

    private lazy var hotkey = HotkeyManager { [weak self] in
        self?.handleHotkeyPress()
    }

    func start() {
        Console.line("flash_asr started. Hotkey: Right Option + Space (registered as Option + Space)")
        Console.line("State: IDLE")
        do {
            try hotkey.start()
        } catch {
            Console.line("Hotkey setup failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    private func handleHotkeyPress() {
        stateQueue.async {
            switch self.state {
            case .idle:
                self.beginListening()
            case .listening:
                self.beginStopping(reason: "Hotkey stop")
            case .stopping:
                break
            }
        }
    }

    private func beginListening() {
        state = .listening
        transcript.reset()
        stopTimeoutWork?.cancel()
        stopTimeoutWork = nil

        Console.clearPartialLine()
        Console.line("State: LISTENING (connecting ASR...)")

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard let self else { return }
            self.stateQueue.async {
                guard self.state == .listening else { return }
                guard granted else {
                    Console.line("Microphone permission denied")
                    self.state = .idle
                    return
                }

                guard let wsURL = URL(string: WS_BASE_URL) else {
                    Console.line("Invalid WS URL")
                    self.state = .idle
                    return
                }

                let client = ASRWebSocketClient(apiKey: API_KEY, url: wsURL, model: MODEL, language: LANGUAGE)
                self.asr = client
                client.onEvent = { [weak self] event in
                    self?.handleASREvent(event)
                }
                client.connect()
            }
        }
    }

    private func beginStopping(reason: String) {
        guard state == .listening else { return }
        state = .stopping

        Console.line("State: STOPPING (\(reason))")
        audio.stop()
        asr?.endSession()

        let work = DispatchWorkItem { [weak self] in
            self?.finalizeAndReset(reason: "Finalize timeout")
        }
        stopTimeoutWork = work
        stateQueue.asyncAfter(deadline: .now() + STOP_FINALIZE_TIMEOUT, execute: work)
    }

    private func handleASREvent(_ event: ASREvent) {
        stateQueue.async {
            switch event {
            case .opened:
                guard self.state == .listening else { return }
                do {
                    try self.audio.start { [weak self] frame in
                        self?.asr?.sendAudioFrame(frame)
                    }
                    Console.line("ASR connected, mic streaming...")
                } catch {
                    Console.line("Audio start failed: \(error.localizedDescription)")
                    self.finalizeAndReset(reason: "Audio start failure")
                }

            case .partial(let text):
                guard self.state == .listening || self.state == .stopping else { return }
                self.transcript.handlePartial(text) { merged in
                    Console.partial(merged)
                }

            case .final(let text):
                guard self.state == .listening || self.state == .stopping else { return }
                self.transcript.handleFinal(text) { merged in
                    Console.partial(merged)
                }

            case .transcriptionFailed(let msg):
                Console.line("ASR transcription failed: \(msg)")

            case .sessionFinished:
                if self.state == .stopping {
                    self.finalizeAndReset(reason: "Session finished")
                }

            case .closed:
                if self.state == .stopping {
                    self.finalizeAndReset(reason: "Socket closed")
                } else if self.state == .listening {
                    self.beginStopping(reason: "Socket closed while listening")
                }

            case .error(let msg):
                Console.line(msg)
                if self.state == .listening {
                    self.beginStopping(reason: "ASR error")
                }
            }
        }
    }

    private func finalizeAndReset(reason: String) {
        guard state != .idle else { return }
        stopTimeoutWork?.cancel()
        stopTimeoutWork = nil

        audio.stop()
        asr?.close()
        asr = nil

        let final = transcript.finalTextAndClearUnstable()
        Console.clearPartialLine()
        if final.isEmpty {
            Console.line("Final text is empty")
        } else {
            clipboard.write(final)
            Console.line("Final: \(final)")
            Console.line("Copied to clipboard")
        }

        state = .idle
        Console.line("State: IDLE (\(reason))")
    }
}

private let app = AppController()
app.start()
RunLoop.main.run()
