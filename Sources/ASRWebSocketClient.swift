import Foundation

enum ASREvent {
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

final class ASRWebSocketClient: NSObject, URLSessionWebSocketDelegate {
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

        guard let session else {
            dispatch(.error("Failed to initialize URLSession"))
            return
        }
        let wsTask = session.webSocketTask(with: request)
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
                    "sample_rate": Int(16_000),
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
