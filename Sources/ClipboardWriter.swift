import AppKit

final class ClipboardWriter {
    func write(_ text: String, asMarkdown: Bool = false) {
        if asMarkdown {
            RichClipboard.shared.writeMultiFormat(markdown: text)
        } else {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
    }
}
