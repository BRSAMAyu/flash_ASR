import Foundation

enum MarkdownLevel: Int, Codable, CaseIterable {
    case faithful = 0
    case light = 1
    case deep = 2

    var displayName: String {
        switch self {
        case .faithful: return "\u{5FE0}\u{5B9E}"
        case .light: return "\u{8F7B}\u{6DA6}"
        case .deep: return "\u{6DF1}\u{6574}"
        }
    }
}

struct TranscriptionRound: Codable, Identifiable {
    let id: UUID
    var originalText: String
    var timestamp: Date
    var markdown: [Int: String]
    var glmMarkdown: [Int: String]

    init(originalText: String) {
        self.id = UUID()
        self.originalText = originalText
        self.timestamp = Date()
        self.markdown = [:]
        self.glmMarkdown = [:]
    }
}

struct TranscriptionSession: Codable, Identifiable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var rounds: [TranscriptionRound]
    var fullRefinement: [Int: String]?
    var glmFullRefinement: [Int: String]?
    var obsidianFilePath: String?

    init(title: String = "") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.rounds = []
        self.fullRefinement = nil
        self.glmFullRefinement = nil
        self.obsidianFilePath = nil
    }

    var allOriginalText: String {
        rounds.map { $0.originalText }.joined(separator: "\n\n")
    }

    func combinedMarkdown(level: MarkdownLevel) -> String {
        if let full = fullRefinement?[level.rawValue], !full.isEmpty {
            return full
        }
        return rounds.compactMap { $0.markdown[level.rawValue] }.joined(separator: "\n\n")
    }

    func combinedGLMMarkdown(level: MarkdownLevel) -> String {
        if let full = glmFullRefinement?[level.rawValue], !full.isEmpty {
            return full
        }
        return rounds.compactMap { $0.glmMarkdown[level.rawValue] }.joined(separator: "\n\n")
    }

    mutating func autoTitle() {
        guard title.isEmpty, let first = rounds.first else { return }
        let prefix = String(first.originalText.prefix(20))
        title = prefix + (first.originalText.count > 20 ? "..." : "")
    }
}
