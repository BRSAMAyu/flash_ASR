import Foundation

final class MiMoClient: NSObject, URLSessionDataDelegate {
    private let apiKey: String
    private let endpoint: URL
    private let model: String
    private let timeout: TimeInterval
    private let temperature: Double
    private let topP: Double
    private let maxTokens: Int
    private let disableThinking: Bool

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var done = false

    var onDelta: ((String) -> Void)?
    var onDone: (() -> Void)?
    var onError: ((String) -> Void)?

    init(apiKey: String, endpoint: URL, model: String,
         timeout: TimeInterval = 60.0,
         temperature: Double = 0.3,
         topP: Double = 0.95,
         maxTokens: Int = 2048,
         disableThinking: Bool = true) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
        self.timeout = timeout
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.disableThinking = disableThinking
    }

    /// v4: parameterized system prompt + user content
    func start(systemPrompt: String, userContent: String) {
        done = false
        buffer.removeAll()

        var payload: [String: Any] = [
            "model": model,
            "stream": true,
            "temperature": temperature,
            "top_p": topP,
            "max_completion_tokens": maxTokens,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ]
        ]
        if disableThinking {
            payload["thinking"] = ["type": "disabled"]
        }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            onError?("MiMo JSON encode failed")
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

    /// v3 compat wrapper
    func start(text: String) {
        let defaultSystemPrompt = MarkdownPrompts.systemPrompt(for: .light)
        start(systemPrompt: defaultSystemPrompt, userContent: text)
    }

    func cancel() {
        done = true
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
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if done { return }
        done = true
        if let error, (error as NSError).code != NSURLErrorCancelled {
            onError?("MiMo request failed: \(error.localizedDescription)")
        }
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
                onDelta?(content)
            }
        }
    }
}
