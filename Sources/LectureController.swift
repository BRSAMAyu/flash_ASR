import Foundation
import AppKit
import UniformTypeIdentifiers

final class LectureController {
    private let settings: SettingsManager
    private let statePublisher: AppStatePublisher
    private let sessionManager: SessionManager
    private let llmService: LLMService
    let lectureImportService = LectureImportService()

    // Shared state with AppController
    weak var appController: AppController?

    init(settings: SettingsManager, statePublisher: AppStatePublisher, sessionManager: SessionManager, llmService: LLMService) {
        self.settings = settings
        self.statePublisher = statePublisher
        self.sessionManager = sessionManager
        self.llmService = llmService
    }

    // MARK: - Import audio

    func importAudio(currentSession: inout TranscriptionSession?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio, .mpeg4Movie]
        panel.message = "\u{9009}\u{62E9}\u{8BFE}\u{5802}\u{5F55}\u{97F3}\u{6587}\u{4EF6}"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Show course profile sheet and wait for result
        DispatchQueue.main.async {
            self.statePublisher.pendingLectureURL = url
            self.statePublisher.showCourseProfileSheet = true
        }
    }

    func completeLectureImport(url: URL, profile: CourseProfile, currentSession: inout TranscriptionSession?) {
        guard !profile.courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            DispatchQueue.main.async {
                self.statePublisher.toastMessage = "\u{8BF7}\u{586B}\u{5199}\u{8BFE}\u{7A0B}\u{540D}"
            }
            return
        }
        CourseProfileStore.shared.upsert(profile)

        var session = sessionManager.createSession()
        let defaultGroup = settings.defaultSessionGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        if !defaultGroup.isEmpty {
            session.groupName = defaultGroup
        }
        session.kind = .lecture
        session.courseName = profile.courseName
        session.lectureDate = Date()
        session.sourceType = "imported"
        session.courseProfile = profile
        session.title = profile.courseName
        sessionManager.updateSession(session)
        currentSession = session

        DispatchQueue.main.async {
            self.statePublisher.currentSession = session
            self.statePublisher.selectedTab = .original
            self.statePublisher.lectureNoteMode = .transcript
            self.statePublisher.activeLectureSessionId = session.id
            self.statePublisher.importProgress = 0
            self.statePublisher.importStageText = "\u{51C6}\u{5907}\u{5BFC}\u{5165}..."
            self.statePublisher.failedLectureSegments = []
            self.statePublisher.lectureTotalSegments = 0
        }

        lectureImportService.importAudio(
            from: url,
            settings: settings,
            onProgress: { [weak self] progress, stage in
                DispatchQueue.main.async {
                    self?.statePublisher.importProgress = progress
                    self?.statePublisher.importStageText = stage
                }
            },
            onComplete: { [weak self] result in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.statePublisher.activeLectureSessionId = nil
                        self.statePublisher.importStageText = ""
                        self.statePublisher.toastMessage = "\u{8BFE}\u{5802}\u{5BFC}\u{5165}\u{5931}\u{8D25}: \(error.localizedDescription)"
                    }
                case .success(let report):
                    guard var latest = self.sessionManager.session(for: session.id) else { return }
                    let raw = report.mergedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleaned = TextPostProcessor.cleanLectureTranscript(raw)
                    if cleaned.isEmpty {
                        DispatchQueue.main.async {
                            self.statePublisher.activeLectureSessionId = nil
                            self.statePublisher.toastMessage = "\u{8BFE}\u{5802}\u{8F6C}\u{5199}\u{7ED3}\u{679C}\u{4E3A}\u{7A7A}"
                        }
                        return
                    }
                    latest.rounds = [TranscriptionRound(originalText: cleaned)]
                    latest.rawTranscript = raw
                    latest.cleanTranscript = cleaned
                    latest.lectureOutputs = nil
                    latest.language = self.settings.language
                    latest.updatedAt = Date()
                    self.sessionManager.updateSession(latest)
                    self.appController?.setCurrentSession(latest)
                    DispatchQueue.main.async {
                        self.statePublisher.currentSession = latest
                        self.statePublisher.originalText = cleaned
                        self.statePublisher.markdownText = cleaned
                        self.statePublisher.editableText = cleaned
                        self.statePublisher.lectureNoteMode = .transcript
                        self.statePublisher.activeLectureSessionId = nil
                        self.statePublisher.importProgress = 1.0
                        self.statePublisher.importStageText = ""
                        self.statePublisher.failedLectureSegments = report.failedSegments
                        self.statePublisher.lectureTotalSegments = report.totalSegments
                        if report.failedSegments.isEmpty {
                            self.statePublisher.toastMessage = "\u{8BFE}\u{5802}\u{8F6C}\u{5199}\u{5B8C}\u{6210}"
                        } else {
                            self.statePublisher.toastMessage = "\u{8F6C}\u{5199}\u{5B8C}\u{6210} (\(report.failedSegments.count) \u{6BB5}\u{5931}\u{8D25}\u{53EF}\u{91CD}\u{8BD5})"
                        }
                    }
                }
            }
        )
    }

    // MARK: - Generate lecture note

    func generateNote(mode: LectureNoteMode, currentSession: TranscriptionSession?) {
        guard let session = currentSession else { return }
        let baseText = (session.kind == .lecture ? session.lectureCleanText : session.allOriginalText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseText.isEmpty else { return }
        llmService.cancelAll()
        DispatchQueue.main.async {
            self.statePublisher.markdownProcessing = true
            self.statePublisher.markdownError = nil
            self.statePublisher.markdownText = ""
            self.statePublisher.lectureNoteMode = mode
        }

        let systemPrompt: String
        switch mode {
        case .transcript:
            systemPrompt = MarkdownPrompts.lectureTranscriptPrompt(profile: session.courseProfile)
        case .lessonPlan:
            systemPrompt = MarkdownPrompts.lectureLessonPlanPrompt(profile: session.courseProfile)
        case .review:
            systemPrompt = MarkdownPrompts.lectureReviewPrompt(profile: session.courseProfile)
        }
        let runMode = settings.llmMode == "glm" ? "glm" : "mimo"

        llmService.startRequest(
            mode: runMode,
            settings: settings,
            systemPrompt: systemPrompt,
            userContent: baseText,
            onDelta: { [weak self] delta, type in
                guard type == .primary else { return }
                DispatchQueue.main.async {
                    self?.statePublisher.markdownText += delta
                }
            },
            onComplete: { [weak self] result, type in
                guard type == .primary else { return }
                guard let self else { return }
                guard var latest = self.appController?.getCurrentSession(), latest.id == session.id else { return }
                if latest.lectureOutputs == nil { latest.lectureOutputs = [:] }
                latest.lectureOutputs?[mode.rawValue] = result
                self.sessionManager.updateSession(latest)
                self.appController?.setCurrentSession(latest)
                DispatchQueue.main.async {
                    self.statePublisher.currentSession = latest
                    self.statePublisher.markdownProcessing = false
                    self.statePublisher.markdownText = result
                    self.statePublisher.editableText = result
                    self.statePublisher.lectureNoteMode = mode
                    self.statePublisher.toastMessage = "\(mode.displayName) \u{5DF2}\u{751F}\u{6210}"
                }
            },
            onError: { [weak self] message, type in
                guard type == .primary else { return }
                DispatchQueue.main.async {
                    self?.statePublisher.markdownProcessing = false
                    self?.statePublisher.markdownError = message
                    self?.statePublisher.toastMessage = "\(mode.displayName) \u{751F}\u{6210}\u{5931}\u{8D25}"
                }
            }
        )
    }

    // MARK: - Retry segment

    func retrySegment(index: Int, currentSession: TranscriptionSession?) {
        lectureImportService.retrySegment(index: index) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let report):
                let sessionId = currentSession?.id ?? self.appController?.getCurrentSession()?.id
                guard let sessionId,
                      var session = self.sessionManager.session(for: sessionId),
                      session.kind == .lecture else { return }
                let cleaned = TextPostProcessor.cleanLectureTranscript(report.mergedText)
                if !cleaned.isEmpty {
                    session.rawTranscript = report.mergedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    session.cleanTranscript = cleaned
                    session.lectureOutputs = nil
                    if session.rounds.isEmpty {
                        session.rounds = [TranscriptionRound(originalText: cleaned)]
                    } else {
                        session.rounds[0].originalText = cleaned
                        if session.rounds.count > 1 {
                            session.rounds = [session.rounds[0]]
                        }
                    }
                }
                self.sessionManager.updateSession(session)
                self.appController?.setCurrentSession(session)
                DispatchQueue.main.async {
                    self.statePublisher.currentSession = session
                    if self.statePublisher.lectureNoteMode == .transcript {
                        self.statePublisher.originalText = cleaned
                        self.statePublisher.markdownText = cleaned
                        self.statePublisher.editableText = cleaned
                    }
                    self.statePublisher.failedLectureSegments = report.failedSegments
                    self.statePublisher.lectureTotalSegments = report.totalSegments
                    self.statePublisher.toastMessage = report.failedSegments.contains(index)
                        ? "\u{7B2C} \(index + 1) \u{6BB5}\u{91CD}\u{8BD5}\u{4ECD}\u{5931}\u{8D25}"
                        : "\u{7B2C} \(index + 1) \u{6BB5}\u{91CD}\u{8BD5}\u{6210}\u{529F}\u{FF0C}\u{5DF2}\u{91CD}\u{65B0}\u{5408}\u{5E76}"
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.statePublisher.toastMessage = "\u{91CD}\u{8BD5}\u{5931}\u{8D25}: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Cancel import

    func cancelImport() {
        lectureImportService.cancel()
        DispatchQueue.main.async {
            self.statePublisher.activeLectureSessionId = nil
            self.statePublisher.importStageText = ""
            self.statePublisher.importProgress = 0
            self.statePublisher.toastMessage = "\u{5DF2}\u{53D6}\u{6D88}\u{8BFE}\u{5802}\u{5BFC}\u{5165}"
        }
    }

    // MARK: - Real-time lecture recording

    func startRecording() {
        // Show course profile sheet; AppController will call beginListening after profile selected
        DispatchQueue.main.async {
            self.statePublisher.pendingLectureURL = nil // nil means real-time, not import
            self.statePublisher.showCourseProfileSheet = true
        }
    }

    func beginLectureSession(profile: CourseProfile, currentSession: inout TranscriptionSession?) {
        guard !profile.courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            DispatchQueue.main.async {
                self.statePublisher.toastMessage = "\u{8BF7}\u{586B}\u{5199}\u{8BFE}\u{7A0B}\u{540D}"
            }
            return
        }
        CourseProfileStore.shared.upsert(profile)

        var session = sessionManager.createSession()
        let defaultGroup = settings.defaultSessionGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        if !defaultGroup.isEmpty {
            session.groupName = defaultGroup
        }
        session.kind = .lecture
        session.courseName = profile.courseName
        session.lectureDate = Date()
        session.sourceType = "realtime"
        session.courseProfile = profile
        session.title = profile.courseName
        sessionManager.updateSession(session)
        currentSession = session

        DispatchQueue.main.async {
            self.statePublisher.currentSession = session
            self.statePublisher.selectedTab = .original
            self.statePublisher.lectureNoteMode = .transcript
            self.statePublisher.lectureRecordingActive = true
        }
    }

    func finishLectureRecording() {
        DispatchQueue.main.async {
            self.statePublisher.lectureRecordingActive = false
            self.statePublisher.toastMessage = "\u{8BFE}\u{5802}\u{5F55}\u{97F3}\u{5DF2}\u{7ED3}\u{675F}"
        }
    }
}
