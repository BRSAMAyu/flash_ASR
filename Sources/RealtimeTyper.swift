import Foundation
import ApplicationServices
import Carbon

final class RealtimeTyper {
    private let queue = DispatchQueue(label: "realtime.typer.queue")
    private var enabled = false
    private var rendered: [Character] = []

    func prepareForSession(realtimeTypeEnabled: Bool) {
        queue.sync {
            enabled = realtimeTypeEnabled && self.checkAccessibility(prompt: true)
            rendered = []
        }
    }

    func apply(text: String) {
        queue.async {
            guard self.enabled else { return }
            let target = Array(text)
            let lcp = self.longestCommonPrefix(self.rendered, target)
            let needDelete = self.rendered.count - lcp
            if needDelete > 0 {
                self.postBackspaces(needDelete)
            }
            if lcp < target.count {
                let suffix = String(target[lcp...])
                self.postText(suffix)
            }
            self.rendered = target
        }
    }

    private func longestCommonPrefix(_ a: [Character], _ b: [Character]) -> Int {
        let n = min(a.count, b.count)
        var i = 0
        while i < n, a[i] == b[i] {
            i += 1
        }
        return i
    }

    private func postBackspaces(_ count: Int) {
        guard count > 0 else { return }
        var left = count
        while left > 0 {
            postKey(keyCode: CGKeyCode(kVK_Delete), keyDown: true)
            postKey(keyCode: CGKeyCode(kVK_Delete), keyDown: false)
            left -= 1
        }
    }

    private func postText(_ text: String) {
        guard !text.isEmpty else { return }
        for scalar in text.unicodeScalars {
            var code = UInt16(scalar.value)
            if let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &code)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &code)
                up.post(tap: .cghidEventTap)
            }
        }
    }

    private func postKey(keyCode: CGKeyCode, keyDown: Bool) {
        guard let e = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown) else { return }
        e.post(tap: .cghidEventTap)
    }

    func checkAccessibility(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
