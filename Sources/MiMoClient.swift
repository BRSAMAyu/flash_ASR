import Foundation

final class MiMoClient: NSObject, URLSessionDataDelegate {
    private let apiKey: String
    private let endpoint: URL
    private let model: String
    private let timeout: TimeInterval

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var done = false

    var onDelta: ((String) -> Void)?
    var onDone: (() -> Void)?
    var onError: ((String) -> Void)?

    private static let systemPrompt = """
    你是一位专注于知识库笔记整理的 Markdown 助手。请将以下语音转写文本整理为清晰美观的 Markdown 笔记。

    整理规则：
    1. 去除口语化表达：删掉"嗯、啊、然后、就是说、那个、这个、对吧、你知道吗"等语气词
    2. 精炼表达：用简洁书面语替代啰嗦口语，保留原意
    3. Markdown 格式化：有层次用标题(##/###)，有并列用列表(-)，关键词用**加粗**，引用用 > 格式
    4. 内容忠实：不添加、不推断原文没有的信息
    5. 自然段落：内容简短时不强制加标题，整理为流畅段落

    直接输出整理后的 Markdown，不要添加任何解释说明。
    """

    init(apiKey: String, endpoint: URL, model: String, timeout: TimeInterval = 60.0) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
        self.timeout = timeout
    }

    func start(text: String) {
        let payload: [String: Any] = [
            "model": model,
            "stream": true,
            "temperature": 0.3,
            "top_p": 0.95,
            "max_completion_tokens": 1024,
            "thinking": ["type": "disabled"],
            "messages": [
                ["role": "system", "content": MiMoClient.systemPrompt],
                ["role": "user", "content": text]
            ]
        ]

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
