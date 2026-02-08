import Foundation

final class FileASRStreamClient: NSObject, URLSessionDataDelegate {
    private let apiKey: String
    private let endpoint: URL
    private let model: String
    private let language: String
    private let timeout: TimeInterval

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var done = false
    private var gotDelta = false
    private var statusCode = 200

    var onDelta: ((String) -> Void)?
    var onDone: (() -> Void)?
    var onError: ((String) -> Void)?

    init(apiKey: String, endpoint: URL, model: String, language: String, timeout: TimeInterval = 90.0) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
        self.language = language
        self.timeout = timeout
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
        req.timeoutInterval = timeout
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
