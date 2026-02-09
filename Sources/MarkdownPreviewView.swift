import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.loadHTMLString(html(markdown: markdown), baseURL: nil)
        return web
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html(markdown: markdown), baseURL: nil)
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
          <div id="content">渲染中...</div>
          <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
          <script>
            const payload = \(json);
            const md = payload.md || "";
            const render = () => {
              const el = document.getElementById("content");
              if (window.marked) {
                marked.setOptions({ gfm: true, breaks: true, headerIds: true, mangle: false });
                el.innerHTML = marked.parse(md);
              } else {
                el.innerText = md;
              }
            };
            setTimeout(render, 0);
          </script>
        </body>
        </html>
        """
    }
}
