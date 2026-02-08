import Foundation

final class TranscriptBuffer {
    private let queue = DispatchQueue(label: "transcript.queue")
    private var stableText = ""
    private var unstableText = ""
    private var lastRender = Date.distantPast

    func reset() {
        queue.sync {
            stableText = ""
            unstableText = ""
            lastRender = .distantPast
        }
    }

    func handlePartial(_ text: String, throttle: TimeInterval = 0.15, render: @escaping (String) -> Void) {
        queue.async {
            self.unstableText = text
            let now = Date()
            guard now.timeIntervalSince(self.lastRender) >= throttle else { return }
            self.lastRender = now
            render(self.combinedTextLocked())
        }
    }

    func handleFinal(_ text: String, render: @escaping (String) -> Void) {
        queue.async {
            if !self.stableText.isEmpty, !self.stableText.hasSuffix(" "), !text.hasPrefix(" ") {
                self.stableText += " "
            }
            self.stableText += text
            self.unstableText = ""
            self.lastRender = Date()
            render(self.combinedTextLocked())
        }
    }

    func finalTextAndClearUnstable() -> String {
        queue.sync {
            if !unstableText.isEmpty {
                if !stableText.isEmpty, !stableText.hasSuffix(" "), !unstableText.hasPrefix(" ") {
                    stableText += " "
                }
                stableText += unstableText
                unstableText = ""
            }
            return stableText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func combinedTextLocked() -> String {
        if stableText.isEmpty { return unstableText }
        if unstableText.isEmpty { return stableText }
        if unstableText.hasPrefix(" ") || stableText.hasSuffix(" ") {
            return stableText + unstableText
        }
        return stableText + " " + unstableText
    }
}
