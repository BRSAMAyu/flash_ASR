import Foundation
import AppKit

enum ExportFormat: String, CaseIterable {
    case markdown = "md"
    case html = "html"
    case plainText = "txt"

    var displayName: String {
        switch self {
        case .markdown: return "Markdown (.md)"
        case .html: return "HTML (.html)"
        case .plainText: return "\u{7EAF}\u{6587}\u{672C} (.txt)"
        }
    }

    var fileExtension: String { rawValue }
}

struct ExportMetadata {
    var title: String
    var date: Date
    var wordCount: Int
    var duration: TimeInterval?
    var tags: [String]
    var language: String
    var roundCount: Int

    func yamlFrontmatter() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var lines = [
            "---",
            "title: \"\(title)\"",
            "date: \(fmt.string(from: date))",
            "words: \(wordCount)",
            "rounds: \(roundCount)",
            "language: \(language)"
        ]
        if let dur = duration {
            let mins = Int(dur) / 60
            let secs = Int(dur) % 60
            lines.append("duration: \"\(mins)m\(secs)s\"")
        }
        if !tags.isEmpty {
            lines.append("tags: [\(tags.map { "\"\($0)\"" }.joined(separator: ", "))]")
        }
        lines.append("---")
        return lines.joined(separator: "\n")
    }
}

enum MarkdownExporter {
    static func export(markdown: String, format: ExportFormat, metadata: ExportMetadata?) -> String {
        switch format {
        case .markdown:
            if let meta = metadata {
                return meta.yamlFrontmatter() + "\n\n" + markdown
            }
            return markdown

        case .html:
            let html = RichClipboard.shared.markdownToHTML(markdown) ?? escapeHTML(markdown)
            return standaloneHTML(title: metadata?.title ?? "FlashASR", body: html)

        case .plainText:
            return stripMarkdown(markdown)
        }
    }

    static func exportToFile(markdown: String, format: ExportFormat, metadata: ExportMetadata?, directory: String, filename: String) -> URL? {
        let content = export(markdown: markdown, format: format, metadata: metadata)
        let name = filename.isEmpty ? "FlashASR-\(Int(Date().timeIntervalSince1970))" : filename
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).\(format.fileExtension)")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            Console.line("Export failed: \(error)")
            return nil
        }
    }

    static func wordCount(_ text: String) -> Int {
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

    private static func stripMarkdown(_ text: String) -> String {
        var result = text
        // Headers
        result = result.replacingOccurrences(of: "(?m)^#{1,6}\\s+", with: "", options: .regularExpression)
        // Bold/italic
        result = result.replacingOccurrences(of: "\\*{1,3}(.+?)\\*{1,3}", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "_{1,3}(.+?)_{1,3}", with: "$1", options: .regularExpression)
        // Strikethrough
        result = result.replacingOccurrences(of: "~~(.+?)~~", with: "$1", options: .regularExpression)
        // Links
        result = result.replacingOccurrences(of: "\\[(.+?)\\]\\(.+?\\)", with: "$1", options: .regularExpression)
        // Inline code
        result = result.replacingOccurrences(of: "`(.+?)`", with: "$1", options: .regularExpression)
        // List markers
        result = result.replacingOccurrences(of: "(?m)^[\\s]*[-*+]\\s+", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?m)^[\\s]*\\d+\\.\\s+", with: "", options: .regularExpression)
        // Blockquote
        result = result.replacingOccurrences(of: "(?m)^>\\s*", with: "", options: .regularExpression)
        // Horizontal rule
        result = result.replacingOccurrences(of: "(?m)^---+\\s*$", with: "", options: .regularExpression)
        return result
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func standaloneHTML(title: String, body: String) -> String {
        """
        <!doctype html>
        <html lang="zh">
        <head>
          <meta charset="utf-8">
          <title>\(escapeHTML(title))</title>
          <style>
            body {
              max-width: 800px; margin: 40px auto; padding: 0 20px;
              font: 16px/1.7 -apple-system, "PingFang SC", sans-serif;
              color: #333; background: #fff;
            }
            h1,h2,h3 { margin: 1em 0 0.5em; }
            h1 { border-bottom: 1px solid #eee; padding-bottom: 0.3em; }
            code { background: #f5f5f5; padding: 1px 5px; border-radius: 3px; }
            pre { background: #f5f5f5; padding: 12px; border-radius: 6px; overflow: auto; }
            pre code { background: none; padding: 0; }
            blockquote { border-left: 3px solid #ddd; margin: 1em 0; padding: 0.3em 1em; color: #666; }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid #ddd; padding: 8px 10px; text-align: left; }
            th { background: #f9f9f9; }
          </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}
