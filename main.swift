import Foundation
import AVFoundation
import AppKit
import Carbon
import ApplicationServices

// Build:
// swiftc /Users/a/code/ASR/flash_ASR/main.swift -framework AVFoundation -framework Carbon -framework AppKit -framework ApplicationServices -o /Users/a/code/ASR/flash_ASR/flash_asr
// Run:
// ./flash_asr

private let API_KEY = "sk-82f726c10954417187fa35d39630fd7c"
private let WS_BASE_URL = "wss://dashscope.aliyuncs.com/api-ws/v1/realtime"
private let MODEL = "qwen3-asr-flash-realtime"
private let FILE_MODEL = "qwen3-asr-flash"
private let FILE_ASR_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
private let LANGUAGE = "zh"

private let SAMPLE_RATE: Double = 16_000
private let CHANNELS: AVAudioChannelCount = 1
private let FRAME_MS = 20
private let FRAME_BYTES = Int(SAMPLE_RATE * Double(FRAME_MS) / 1000.0) * MemoryLayout<Int16>.size

private let SILENCE_THRESHOLD: Int32 = 220
private let PARTIAL_PRINT_THROTTLE: TimeInterval = 0.15
private let STOP_FINALIZE_TIMEOUT: TimeInterval = 2.0
private let FILE_ASR_TIMEOUT: TimeInterval = 90.0
private let AUTO_STOP_AFTER_SPEECH_STOPPED = true
private let AUTO_STOP_DELAY: TimeInterval = 2.2
private let REALTIME_TYPE_TO_FOCUSED_APP = true
private let MAX_FILE_MODE_SECONDS: Double = 300.0

enum AppState {
    case idle
    case listening
    case stopping
}

private enum CaptureMode {
    case realtime
    case fileFlash
}

private enum TriggerAction {
    case realtimeToggle
    case fileToggle
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
    case speechStarted
    case speechStopped
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
        case "input_audio_buffer.speech_started":
            dispatch(.speechStarted)
        case "input_audio_buffer.speech_stopped":
            dispatch(.speechStopped)
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
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        dispatch(.error("WebSocket closed: code=\(closeCode.rawValue) reason=\(reasonText)"))
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
    private var dropSilenceFrames = true
    private var frameHandler: ((Data) -> Void)?

    func start(dropSilenceFrames: Bool = true, frameHandler: @escaping (Data) -> Void) throws {
        guard !running else { return }
        running = true
        self.dropSilenceFrames = dropSilenceFrames
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
            if !dropSilenceFrames || isVoice(frameData) {
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

private func makeWav(pcm16Mono16k pcm: Data, sampleRate: Int, channels: Int) -> Data {
    let bitsPerSample = 16
    let byteRate = sampleRate * channels * bitsPerSample / 8
    let blockAlign = channels * bitsPerSample / 8
    let dataSize = Int32(pcm.count)
    let riffSize = Int32(36) + dataSize

    var out = Data()
    out.append("RIFF".data(using: .ascii)!)
    out.append(contentsOf: withUnsafeBytes(of: riffSize.littleEndian, Array.init))
    out.append("WAVE".data(using: .ascii)!)
    out.append("fmt ".data(using: .ascii)!)

    let fmtChunkSize: Int32 = 16
    let audioFormat: Int16 = 1
    let numChannels: Int16 = Int16(channels)
    let sr: Int32 = Int32(sampleRate)
    let br: Int32 = Int32(byteRate)
    let ba: Int16 = Int16(blockAlign)
    let bps: Int16 = Int16(bitsPerSample)

    out.append(contentsOf: withUnsafeBytes(of: fmtChunkSize.littleEndian, Array.init))
    out.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian, Array.init))
    out.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian, Array.init))
    out.append(contentsOf: withUnsafeBytes(of: sr.littleEndian, Array.init))
    out.append(contentsOf: withUnsafeBytes(of: br.littleEndian, Array.init))
    out.append(contentsOf: withUnsafeBytes(of: ba.littleEndian, Array.init))
    out.append(contentsOf: withUnsafeBytes(of: bps.littleEndian, Array.init))

    out.append("data".data(using: .ascii)!)
    out.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))
    out.append(pcm)
    return out
}

private final class ClipboardWriter {
    func write(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

private final class FileASRStreamClient: NSObject, URLSessionDataDelegate {
    private let apiKey: String
    private let endpoint: URL
    private let model: String
    private let language: String

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var done = false
    private var gotDelta = false
    private var statusCode = 200

    var onDelta: ((String) -> Void)?
    var onDone: (() -> Void)?
    var onError: ((String) -> Void)?

    init(apiKey: String, endpoint: URL, model: String, language: String) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
        self.language = language
    }

    func start(base64Wav: String) {
        let audioDataURI = "data:audio/wav;base64,\(base64Wav)"
        let payload: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_audio",
                            "input_audio": [
                                "data": audioDataURI,
                                "format": "wav"
                            ]
                        ]
                    ]
                ]
            ],
            "asr_options": [
                "language": language,
                "enable_itn": false
            ]
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            onError?("File ASR JSON encode failed")
            return
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.httpBody = body
        req.timeoutInterval = FILE_ASR_TIMEOUT
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("text/event-stream", forHTTPHeaderField: "Accept")

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: req)
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if done { return }
        buffer.append(data)
        parseSSE()
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            statusCode = http.statusCode
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if done { return }
        if let error {
            onError?("File ASR stream failed: \(error.localizedDescription)")
        } else if !gotDelta {
            let raw = String(data: buffer, encoding: .utf8) ?? ""
            if !raw.isEmpty {
                onError?("File ASR empty stream, http=\(statusCode), raw=\(raw.prefix(320))")
            } else {
                onError?("File ASR empty stream, http=\(statusCode)")
            }
        }
        done = true
        onDone?()
    }

    private func parseSSE() {
        while let range = buffer.range(of: Data("\n".utf8)) {
            let lineData = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            guard var line = String(data: lineData, encoding: .utf8) else { continue }
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" {
                done = true
                onDone?()
                return
            }
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any],
                  let content = delta["content"] as? String
            else { continue }
            if !content.isEmpty {
                gotDelta = true
                onDelta?(content)
            }
        }
    }
}

private final class RealtimeTyper {
    private let queue = DispatchQueue(label: "realtime.typer.queue")
    private var enabled = false
    private var rendered: [Character] = []

    func prepareForSession() {
        queue.sync {
            enabled = REALTIME_TYPE_TO_FOCUSED_APP && self.checkAccessibility(prompt: true)
            rendered = []
        }
    }

    func apply(text: String) {
        queue.async {
            guard self.enabled else { return }
            let target = Array(text)
            let lcp = self.longestCommonPrefix(self.rendered, target)
            let needDelete = self.rendered.count - lcp
            if needDelete > 0 {
                self.postBackspaces(needDelete)
            }
            if lcp < target.count {
                let suffix = String(target[lcp...])
                self.postText(suffix)
            }
            self.rendered = target
        }
    }

    private func longestCommonPrefix(_ a: [Character], _ b: [Character]) -> Int {
        let n = min(a.count, b.count)
        var i = 0
        while i < n, a[i] == b[i] {
            i += 1
        }
        return i
    }

    private func postBackspaces(_ count: Int) {
        guard count > 0 else { return }
        var left = count
        while left > 0 {
            postKey(keyCode: CGKeyCode(kVK_Delete), keyDown: true)
            postKey(keyCode: CGKeyCode(kVK_Delete), keyDown: false)
            left -= 1
        }
    }

    private func postText(_ text: String) {
        guard !text.isEmpty else { return }
        for scalar in text.unicodeScalars {
            var code = UInt16(scalar.value)
            if let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &code)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &code)
                up.post(tap: .cghidEventTap)
            }
        }
    }

    private func postKey(keyCode: CGKeyCode, keyDown: Bool) {
        guard let e = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown) else { return }
        e.post(tap: .cghidEventTap)
    }

    private func checkAccessibility(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

private final class GlobalKeyTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let onTrigger: (TriggerAction) -> Void
    init(onTrigger: @escaping (TriggerAction) -> Void) {
        self.onTrigger = onTrigger
    }

    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let callback: CGEventTapCallBack = { _, type, event, userData in
            guard let userData else {
                return Unmanaged.passUnretained(event)
            }
            let me = Unmanaged<GlobalKeyTap>.fromOpaque(userData).takeUnretainedValue()
            if type == .keyDown {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let optionDown = flags.contains(.maskAlternate)
                if optionDown && keyCode == Int64(kVK_Space) {
                    me.onTrigger(.realtimeToggle)
                    return nil
                }
                if optionDown && keyCode == Int64(kVK_LeftArrow) {
                    me.onTrigger(.fileToggle)
                    return nil
                }
                return Unmanaged.passUnretained(event)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: userData
        ) else {
            return false
        }

        tap = eventTap
        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            tap = nil
            return false
        }
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            self.source = nil
        }
        if let tap {
            CFMachPortInvalidate(tap)
            self.tap = nil
        }
    }
}

private final class AppController {
    private let stateQueue = DispatchQueue(label: "app.state.queue")

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

    private lazy var keyTap = GlobalKeyTap { [weak self] action in
        self?.handleTrigger(action)
    }

    func start() {
        Console.line("flash_asr started.")
        Console.line("Hotkeys: Option+Space => realtime model, Option+LeftArrow => qwen3-asr-flash file mode.")
        Console.line("Workflow: auto-stop after silence grace window (conservative).")
        Console.line("For realtime typing, focus target text field first and grant Accessibility if prompted.")
        Console.line("State: IDLE")

        if keyTap.start() {
            Console.line("Global hotkey listener enabled.")
        } else {
            Console.line("Global key event tap unavailable. Enable FlashASR in Privacy & Security -> Accessibility and Input Monitoring.")
        }
    }

    private func handleTrigger(_ action: TriggerAction) {
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
        typer.prepareForSession()
        stopTimeoutWork?.cancel()
        stopTimeoutWork = nil
        autoStopWork?.cancel()
        autoStopWork = nil

        Console.clearPartialLine()
        switch mode {
        case .realtime:
            Console.line("State: LISTENING (realtime ASR connecting...)")
        case .fileFlash:
            Console.line("State: LISTENING (file ASR recording, max 5 min...)")
        }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        Console.line("Microphone auth status: \(status.rawValue) (0:notDetermined 1:restricted 2:denied 3:authorized)")

        let continueStart: () -> Void = { [weak self] in
            guard let self else { return }
            guard self.state == .listening, self.mode == mode else { return }

            switch mode {
            case .realtime:
                guard let wsURL = URL(string: WS_BASE_URL) else {
                    Console.line("Invalid realtime WS URL")
                    self.state = .idle
                    self.mode = nil
                    return
                }
                let client = ASRWebSocketClient(apiKey: API_KEY, url: wsURL, model: MODEL, language: LANGUAGE)
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
                        return
                    }
                    continueStart()
                }
            }
        case .denied, .restricted:
            Console.line("Microphone permission denied/restricted. Enable Terminal in: System Settings -> Privacy & Security -> Microphone")
            state = .idle
            self.mode = nil
        @unknown default:
            Console.line("Unknown microphone auth status")
            state = .idle
            self.mode = nil
        }
    }

    private func handleFileFrame(_ frame: Data) {
        stateQueue.async {
            guard self.state == .listening, self.mode == .fileFlash else { return }
            self.recordedPCM.append(frame)
            let elapsed = Date().timeIntervalSince(self.recordStartedAt)
            if elapsed >= MAX_FILE_MODE_SECONDS {
                self.beginStopping(reason: "Reached 5 minute limit")
            }
        }
    }

    private func beginStopping(reason: String) {
        guard state == .listening else { return }
        state = .stopping

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
            stateQueue.asyncAfter(deadline: .now() + STOP_FINALIZE_TIMEOUT, execute: work)
            return
        }

        // file mode: send recorded audio to qwen3-asr-flash streaming endpoint
        doStartFileASRStreaming()

        let work = DispatchWorkItem { [weak self] in
            self?.finalizeAndReset(reason: "File ASR timeout", overrideFinal: self?.fileStreamText ?? "")
        }
        stopTimeoutWork = work
        stateQueue.asyncAfter(deadline: .now() + FILE_ASR_TIMEOUT, execute: work)
    }

    private func doStartFileASRStreaming() {
        guard mode == .fileFlash else { return }
        guard !recordedPCM.isEmpty else {
            finalizeAndReset(reason: "No recorded audio", overrideFinal: "")
            return
        }
        guard let endpoint = URL(string: FILE_ASR_URL) else {
            finalizeAndReset(reason: "Invalid File ASR URL", overrideFinal: "")
            return
        }
        let wav = makeWav(pcm16Mono16k: recordedPCM, sampleRate: Int(SAMPLE_RATE), channels: Int(CHANNELS))
        let base64 = wav.base64EncodedString()
        let durationSec = Double(recordedPCM.count) / Double(Int(SAMPLE_RATE) * MemoryLayout<Int16>.size)
        Console.line(String(format: "Recorded audio: %.2fs, %d bytes PCM", durationSec, recordedPCM.count))
        Console.line("Uploading recorded audio to qwen3-asr-flash (streaming response)...")

        let client = FileASRStreamClient(apiKey: API_KEY, endpoint: endpoint, model: FILE_MODEL, language: LANGUAGE)
        fileAsr = client
        client.onDelta = { [weak self] delta in
            self?.stateQueue.async {
                guard let self, self.state == .stopping, self.mode == .fileFlash else { return }
                self.fileStreamText += delta
                Console.partial(self.fileStreamText)
                self.typer.apply(text: self.fileStreamText)
            }
        }
        client.onError = { [weak self] msg in
            self?.stateQueue.async {
                Console.line(msg)
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
                }

            case .final(let text):
                guard (self.state == .listening || self.state == .stopping), self.mode == .realtime else { return }
                self.transcript.handleFinal(text) { merged in
                    Console.partial(merged)
                    self.typer.apply(text: merged)
                }

            case .speechStarted:
                guard self.mode == .realtime else { return }
                self.autoStopWork?.cancel()
                self.autoStopWork = nil

            case .speechStopped:
                guard self.state == .listening, self.mode == .realtime, AUTO_STOP_AFTER_SPEECH_STOPPED else { return }
                self.autoStopWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    if self.state == .listening {
                        self.beginStopping(reason: "Auto stop after speech end")
                    }
                }
                self.autoStopWork = work
                self.stateQueue.asyncAfter(deadline: .now() + AUTO_STOP_DELAY, execute: work)

            case .transcriptionFailed(let msg):
                Console.line("ASR transcription failed: \(msg)")

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

        let final = (overrideFinal ?? transcript.finalTextAndClearUnstable()).trimmingCharacters(in: .whitespacesAndNewlines)
        Console.clearPartialLine()
        if final.isEmpty {
            Console.line("Final text is empty")
        } else {
            clipboard.write(final)
            Console.line("Final: \(final)")
            Console.line("Copied to clipboard")
        }

        state = .idle
        mode = nil
        recordedPCM.removeAll(keepingCapacity: false)
        fileStreamText = ""
        Console.line("State: IDLE (\(reason))")
    }

    deinit {
        keyTap.stop()
    }
}

private let app = AppController()
app.start()
RunLoop.main.run()
