import AppKit
import JavaScriptCore

final class RichClipboard {
    static let shared = RichClipboard()
    private var jsContext: JSContext?
    private var markedReady = false

    private init() {
        setupJSContext()
    }

    private func setupJSContext() {
        guard let js = MarkdownPreviewView.loadBundledMarkedJS() else { return }
        let ctx = JSContext()!
        ctx.evaluateScript(js)
        // Verify marked is available
        let test = ctx.evaluateScript("typeof marked !== 'undefined' && typeof marked.parse === 'function'")
        markedReady = test?.toBool() == true
        if markedReady {
            jsContext = ctx
        }
    }

    func markdownToHTML(_ markdown: String) -> String? {
        guard markedReady, let ctx = jsContext else { return nil }
        ctx.setObject(markdown, forKeyedSubscript: "_inputMd" as NSString)
        let result = ctx.evaluateScript("marked.parse(_inputMd)")
        return result?.toString()
    }

    func writeMultiFormat(markdown: String) {
        let pb = NSPasteboard.general
        pb.clearContents()

        // Always write plain text
        pb.setString(markdown, forType: .string)

        // Convert to HTML
        guard let html = markdownToHTML(markdown) else { return }
        let styledHTML = """
        <html><head><meta charset="utf-8"><style>
        body { font: 14px/1.6 -apple-system, "PingFang SC", sans-serif; }
        h1,h2,h3 { margin: 0.8em 0 0.4em; }
        p { margin: 0.5em 0; }
        ul,ol { margin: 0.5em 0; }
        code { background: #f0f0f0; padding: 1px 4px; border-radius: 3px; font-size: 0.9em; }
        pre { background: #f0f0f0; padding: 8px; border-radius: 6px; overflow: auto; }
        pre code { background: none; padding: 0; }
        blockquote { border-left: 3px solid #ccc; margin: 0.5em 0; padding: 0.2em 0.8em; color: #666; }
        table { border-collapse: collapse; }
        th, td { border: 1px solid #ddd; padding: 6px 8px; }
        </style></head><body>\(html)</body></html>
        """

        // Write HTML
        if let htmlData = styledHTML.data(using: .utf8) {
            pb.setData(htmlData, forType: .html)
        }

        // Write RTF
        if let attrStr = try? NSAttributedString(
            data: Data(styledHTML.utf8),
            options: [.documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ) {
            if let rtfData = try? attrStr.data(from: NSRange(location: 0, length: attrStr.length),
                                                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                pb.setData(rtfData, forType: .rtf)
            }
        }
    }
}
