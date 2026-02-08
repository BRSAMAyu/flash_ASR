import Foundation

final class Console {
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
