import Foundation

enum DisplayTextResolver {
    static func resolve(appState: AppStatePublisher, selectedTab: MarkdownTab, showGLMVersion: Bool, lectureNoteMode: LectureNoteMode) -> String {
        if let session = appState.currentSession, lectureNoteMode != .transcript {
            if appState.markdownProcessing && !appState.markdownText.isEmpty {
                return appState.markdownText
            }
            let saved = session.lectureOutputs?[lectureNoteMode.rawValue] ?? ""
            if !saved.isEmpty { return saved }
            if !appState.markdownText.isEmpty { return appState.markdownText }
        }

        if let session = appState.currentSession, session.kind == .lecture, lectureNoteMode == .transcript {
            return session.lectureCleanText
        }

        if selectedTab == .original {
            if let session = appState.currentSession, !session.allOriginalText.isEmpty {
                return session.allOriginalText
            }
            if !appState.originalText.isEmpty { return appState.originalText }
            if !appState.lastFinalText.isEmpty { return appState.lastFinalText }
            return appState.currentTranscript
        }

        // GLM version
        if showGLMVersion {
            if appState.glmProcessing && !appState.glmText.isEmpty {
                return appState.glmText
            }
            if let session = appState.currentSession,
               let level = selectedTab.markdownLevel {
                let glmCombined = session.combinedGLMMarkdown(level: level)
                if !glmCombined.isEmpty { return glmCombined }
            }
        }

        // Primary markdown
        if appState.markdownProcessing && !appState.markdownText.isEmpty {
            return appState.markdownText
        }

        if let session = appState.currentSession,
           let level = selectedTab.markdownLevel {
            let combined = session.combinedMarkdown(level: level)
            if !combined.isEmpty { return combined }
        }

        return appState.markdownText
    }
}
