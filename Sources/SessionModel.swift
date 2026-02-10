import Foundation

enum SessionKind: String, Codable, CaseIterable {
    case regular
    case lecture
}

enum LectureNoteMode: String, Codable, CaseIterable {
    case transcript
    case lessonPlan
    case review

    var displayName: String {
        switch self {
        case .transcript: return "课堂转写"
        case .lessonPlan: return "教案"
        case .review: return "复习"
        }
    }
}

struct CourseProfile: Codable, Equatable {
    var courseName: String
    var majorKeywords: [String]
    var examFocus: String
    var forbiddenSimplifications: [String]
    var updatedAt: Date

    init(
        courseName: String,
        majorKeywords: [String] = [],
        examFocus: String = "",
        forbiddenSimplifications: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.courseName = courseName
        self.majorKeywords = majorKeywords
        self.examFocus = examFocus
        self.forbiddenSimplifications = forbiddenSimplifications
        self.updatedAt = updatedAt
    }
}

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
    // v6.1: lecture
    var kind: SessionKind
    var courseName: String?
    var lectureDate: Date?
    var chapter: String?
    var sourceType: String?
    var lectureOutputs: [String: String]?
    var courseProfile: CourseProfile?
    // v6.3: dual-track transcript storage for lecture scenarios
    var rawTranscript: String?
    var cleanTranscript: String?

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
        self.kind = .regular
        self.courseName = nil
        self.lectureDate = nil
        self.chapter = nil
        self.sourceType = nil
        self.lectureOutputs = nil
        self.courseProfile = nil
        self.rawTranscript = nil
        self.cleanTranscript = nil
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
        kind = try container.decodeIfPresent(SessionKind.self, forKey: .kind) ?? .regular
        courseName = try container.decodeIfPresent(String.self, forKey: .courseName)
        lectureDate = try container.decodeIfPresent(Date.self, forKey: .lectureDate)
        chapter = try container.decodeIfPresent(String.self, forKey: .chapter)
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType)
        lectureOutputs = try container.decodeIfPresent([String: String].self, forKey: .lectureOutputs)
        courseProfile = try container.decodeIfPresent(CourseProfile.self, forKey: .courseProfile)
        rawTranscript = try container.decodeIfPresent(String.self, forKey: .rawTranscript)
        cleanTranscript = try container.decodeIfPresent(String.self, forKey: .cleanTranscript)
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
        if !title.isEmpty { return title }
        if let name = courseName, !name.isEmpty { return name }
        return "\u{672A}\u{547D}\u{540D}"
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

    var hasLectureNotes: Bool {
        let lesson = lectureOutputs?[LectureNoteMode.lessonPlan.rawValue] ?? ""
        let review = lectureOutputs?[LectureNoteMode.review.rawValue] ?? ""
        return !lesson.isEmpty || !review.isEmpty
    }

    var lectureRawText: String {
        let candidate = rawTranscript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !candidate.isEmpty { return candidate }
        return allOriginalText
    }

    var lectureCleanText: String {
        let candidate = cleanTranscript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !candidate.isEmpty { return candidate }
        return allOriginalText
    }
}
