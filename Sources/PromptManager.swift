import Foundation

final class PromptManager {
    static let shared = PromptManager()

    private let fileManager = FileManager.default

    private var promptsDir: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("FlashASR/prompts", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {}

    private func fileURL(for level: MarkdownLevel) -> URL {
        promptsDir.appendingPathComponent("\(level.rawValue).txt")
    }

    func loadPrompt(for level: MarkdownLevel) -> String? {
        let url = fileURL(for: level)
        guard fileManager.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return content
    }

    func savePrompt(_ prompt: String, for level: MarkdownLevel) {
        let url = fileURL(for: level)
        try? prompt.write(to: url, atomically: true, encoding: .utf8)
    }

    func resetPrompt(for level: MarkdownLevel) {
        let url = fileURL(for: level)
        try? fileManager.removeItem(at: url)
    }

    func hasCustomPrompt(for level: MarkdownLevel) -> Bool {
        loadPrompt(for: level) != nil
    }
}
