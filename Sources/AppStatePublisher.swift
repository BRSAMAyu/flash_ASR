import Foundation
import SwiftUI

enum MarkdownTab: Int, CaseIterable {
    case original = -1
    case faithful = 0
    case light = 1
    case deep = 2

    var displayName: String {
        switch self {
        case .original: return "\u{539F}\u{6587}"
        case .faithful: return "\u{5FE0}\u{5B9E}"
        case .light: return "\u{8F7B}\u{6DA6}"
        case .deep: return "\u{6DF1}\u{6574}"
        }
    }

    var markdownLevel: MarkdownLevel? {
        switch self {
        case .original: return nil
        case .faithful: return .faithful
        case .light: return .light
        case .deep: return .deep
        }
    }
}

final class AppStatePublisher: ObservableObject {
    @Published var state: AppState = .idle
    @Published var mode: CaptureMode? = nil
    @Published var currentTranscript: String = ""
    @Published var lastFinalText: String = ""
    @Published var errorMessage: String? = nil
    @Published var permissions = PermissionSnapshot(microphone: false, accessibility: false, inputMonitoring: false)
    @Published var serviceReady: Bool = false
    @Published var remainingRecordSeconds: Int? = nil
    @Published var hotkeyConflictRealtime: Bool = false
    @Published var hotkeyConflictFile: Bool = false

    // Markdown mode (v3 compat)
    @Published var markdownProcessing: Bool = false
    @Published var markdownText: String = ""
    @Published var originalText: String = ""
    @Published var markdownError: String? = nil

    // v4: Session & multi-level
    @Published var currentSession: TranscriptionSession? = nil
    @Published var selectedTab: MarkdownTab = .original
    @Published var generatingLevel: MarkdownLevel? = nil
    @Published var audioLevel: Float = 0.0

    // v4.1: Toast feedback
    @Published var toastMessage: String? = nil

    // v4.1.1: GLM dual engine
    @Published var glmProcessing: Bool = false
    @Published var glmText: String = ""
    @Published var showGLMVersion: Bool = false
    @Published var glmGeneratingLevel: MarkdownLevel? = nil

    // v5.2 editor + transform
    @Published var editableText: String = ""
    @Published var panelEditingEnabled: Bool = false
    @Published var canUndoTransform: Bool = false

    // v6.1 lecture import
    @Published var importProgress: Double = 0.0
    @Published var importStageText: String = ""
    @Published var activeLectureSessionId: UUID? = nil
    @Published var lectureNoteMode: LectureNoteMode = .transcript
    @Published var failedLectureSegments: [Int] = []
    @Published var lectureTotalSegments: Int = 0

    // v6.2 lecture recording + course profile sheet
    @Published var lectureRecordingActive: Bool = false
    @Published var showCourseProfileSheet: Bool = false
    @Published var pendingLectureURL: URL? = nil
}
