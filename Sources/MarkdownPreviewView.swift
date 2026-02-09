import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        context.coordinator.lastMarkdown = markdown
        context.coordinator.webView = web
        web.loadHTMLString(html(markdown: markdown), baseURL: nil)
        return web
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coord = context.coordinator
        guard markdown != coord.lastMarkdown else { return }
        coord.pendingMarkdown = markdown
        coord.scheduleUpdate()
    }

    private static func jsStringLiteral(_ str: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: str, options: .fragmentsAllowed),
              let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        // JSONSerialization produces a quoted string like "hello\nworld"
        return json
    }

    private func html(markdown: String) -> String {
        let json: String = {
            if let data = try? JSONSerialization.data(withJSONObject: ["md": markdown], options: []),
               let raw = String(data: data, encoding: .utf8) {
                return raw
            }
            return "{\"md\":\"\"}"
        }()

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <style>
            :root {
              --bg: #1e1e1e;
              --fg: #d4d4d4;
              --muted: #a0a0a0;
              --accent: #7aa2f7;
              --border: #3a3a3a;
              --code-bg: #2a2a2a;
              --quote: #6a9955;
            }
            html, body {
              margin: 0; padding: 0; background: transparent; color: var(--fg);
              font: 14px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", sans-serif;
            }
            #content { padding: 14px; }
            h1,h2,h3,h4,h5,h6 { margin: 1.1em 0 0.45em; line-height: 1.25; }
            h1 { font-size: 1.95em; border-bottom: 1px solid var(--border); padding-bottom: 0.28em; }
            h2 { font-size: 1.55em; border-bottom: 1px solid var(--border); padding-bottom: 0.2em; }
            h3 { font-size: 1.3em; }
            h4 { font-size: 1.1em; }
            p { margin: 0.6em 0; }
            ul,ol { margin: 0.5em 0 0.8em 1.2em; }
            li { margin: 0.2em 0; }
            li input[type="checkbox"] { margin-right: 0.45em; transform: translateY(1px); }
            a { color: var(--accent); text-decoration: none; }
            a:hover { text-decoration: underline; }
            blockquote {
              margin: 0.9em 0; padding: 0.2em 0.9em; border-left: 3px solid var(--quote);
              color: var(--muted); background: rgba(255,255,255,0.02);
            }
            code {
              font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
              background: var(--code-bg); padding: 0.1em 0.35em; border-radius: 4px;
            }
            pre {
              background: var(--code-bg); padding: 0.85em; border-radius: 8px;
              overflow: auto; border: 1px solid var(--border);
            }
            pre code { padding: 0; background: transparent; border-radius: 0; }
            table { border-collapse: collapse; width: 100%; margin: 0.9em 0; }
            th, td { border: 1px solid var(--border); padding: 8px 10px; text-align: left; vertical-align: top; }
            th { background: rgba(255,255,255,0.06); font-weight: 600; }
            hr { border: none; border-top: 1px solid var(--border); margin: 1em 0; }
            img { max-width: 100%; }
          </style>
        </head>
        <body>
          <div id="content">\u{6E32}\u{67D3}\u{4E2D}...</div>
          <script>
            var _markedReady = false;
            function render(md) {
              var el = document.getElementById("content");
              if (_markedReady && window.marked) {
                marked.setOptions({ gfm: true, breaks: true, headerIds: true, mangle: false });
                el.innerHTML = marked.parse(md);
              } else {
                el.innerText = md;
              }
            }
            function updateContent(md) {
              render(md);
            }
            var _initialMd = (\(json)).md || "";
          </script>
          <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"
                  onload="_markedReady=true; render(_initialMd);"
                  onerror="render(_initialMd);"></script>
        </body>
        </html>
        """
    }

    class Coordinator {
        var lastMarkdown: String = ""
        var pendingMarkdown: String?
        weak var webView: WKWebView?
        private var debounceWork: DispatchWorkItem?

        func scheduleUpdate() {
            debounceWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.flushUpdate()
            }
            debounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        }

        private func flushUpdate() {
            guard let md = pendingMarkdown, let webView else { return }
            pendingMarkdown = nil
            lastMarkdown = md
            let jsLiteral = MarkdownPreviewView.jsStringLiteral(md)
            webView.evaluateJavaScript("updateContent(\(jsLiteral))") { [weak self] _, error in
                if error != nil {
                    // JS not ready yet, fall back to full reload
                    let html = MarkdownPreviewView(markdown: md).html(markdown: md)
                    webView.loadHTMLString(html, baseURL: nil)
                    self?.lastMarkdown = md
                }
            }
        }
    }
}
