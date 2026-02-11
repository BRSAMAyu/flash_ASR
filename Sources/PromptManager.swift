import Foundation

enum PromptProfile: String, CaseIterable, Identifiable {
    case faithful
    case light
    case deep
    case lectureTranscript
    case lectureLessonPlan
    case lectureReview

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .faithful: return "\u{5FE0}\u{5B9E}\u{6A21}\u{5F0F}"
        case .light: return "\u{8F7B}\u{6DA6}\u{6A21}\u{5F0F}"
        case .deep: return "\u{6DF1}\u{6574}\u{6A21}\u{5F0F}"
        case .lectureTranscript: return "\u{8BFE}\u{5802}\u{8F6C}\u{5199}"
        case .lectureLessonPlan: return "\u{8BFE}\u{5802}\u{6559}\u{6848}"
        case .lectureReview: return "\u{8BFE}\u{5802}\u{590D}\u{4E60}"
        }
    }
}

final class PromptManager {
    static let shared = PromptManager()

    private let fileManager = FileManager.default

    private var promptsDir: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = appSupport.appendingPathComponent("FlashASR/prompts", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {}

    private func fileURL(for profile: PromptProfile) -> URL {
        promptsDir.appendingPathComponent("\(profile.rawValue).txt")
    }

    private func profile(for level: MarkdownLevel) -> PromptProfile {
        switch level {
        case .faithful: return .faithful
        case .light: return .light
        case .deep: return .deep
        }
    }

    func loadPrompt(for level: MarkdownLevel) -> String? {
        loadPrompt(for: profile(for: level))
    }

    func loadPrompt(for profile: PromptProfile) -> String? {
        let url = fileURL(for: profile)
        guard fileManager.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return content
    }

    func savePrompt(_ prompt: String, for level: MarkdownLevel) {
        savePrompt(prompt, for: profile(for: level))
    }

    func savePrompt(_ prompt: String, for profile: PromptProfile) {
        let url = fileURL(for: profile)
        try? prompt.write(to: url, atomically: true, encoding: .utf8)
    }

    func resetPrompt(for level: MarkdownLevel) {
        resetPrompt(for: profile(for: level))
    }

    func resetPrompt(for profile: PromptProfile) {
        let url = fileURL(for: profile)
        try? fileManager.removeItem(at: url)
    }

    func hasCustomPrompt(for level: MarkdownLevel) -> Bool {
        hasCustomPrompt(for: profile(for: level))
    }

    func hasCustomPrompt(for profile: PromptProfile) -> Bool {
        loadPrompt(for: profile) != nil
    }

    func defaultPrompt(for profile: PromptProfile) -> String {
        switch profile {
        case .faithful:
            return MarkdownPrompts.defaultSystemPrompt(for: .faithful)
        case .light:
            return MarkdownPrompts.defaultSystemPrompt(for: .light)
        case .deep:
            return MarkdownPrompts.defaultSystemPrompt(for: .deep)
        case .lectureTranscript:
            return MarkdownPrompts.defaultLectureTranscriptPrompt(profile: nil)
        case .lectureLessonPlan:
            return MarkdownPrompts.defaultLectureLessonPlanPrompt(profile: nil)
        case .lectureReview:
            return MarkdownPrompts.defaultLectureReviewPrompt(profile: nil)
        }
    }
}
