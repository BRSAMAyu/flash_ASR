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
    // v6.0: metadata
    var tags: [String]
    var recordingDuration: TimeInterval?
    var language: String

    init(title: String = "") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.rounds = []
        self.fullRefinement = nil
        self.glmFullRefinement = nil
        self.obsidianFilePath = nil
        self.tags = []
        self.recordingDuration = nil
        self.language = "zh"
    }

    // Codable backward compatibility: new fields have defaults
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        rounds = try container.decode([TranscriptionRound].self, forKey: .rounds)
        fullRefinement = try container.decodeIfPresent([Int: String].self, forKey: .fullRefinement)
        glmFullRefinement = try container.decodeIfPresent([Int: String].self, forKey: .glmFullRefinement)
        obsidianFilePath = try container.decodeIfPresent(String.self, forKey: .obsidianFilePath)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        recordingDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .recordingDuration)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "zh"
    }

    var wordCount: Int {
        let text = allOriginalText
        var count = 0
        var inLatinWord = false
        for scalar in text.unicodeScalars {
            if scalar.value >= 0x4E00 && scalar.value <= 0x9FFF
                || scalar.value >= 0x3400 && scalar.value <= 0x4DBF
                || scalar.value >= 0x3000 && scalar.value <= 0x303F {
                count += 1
                if inLatinWord { count += 1; inLatinWord = false }
            } else if scalar.properties.isAlphabetic {
                if !inLatinWord { inLatinWord = true }
            } else {
                if inLatinWord { count += 1; inLatinWord = false }
            }
        }
        if inLatinWord { count += 1 }
        return count
    }

    var displayTitle: String {
        title.isEmpty ? "\u{672A}\u{547D}\u{540D}" : title
    }

    var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd HH:mm"
        return fmt.string(from: createdAt)
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
