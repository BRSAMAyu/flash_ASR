import SwiftUI

struct MarkdownPreviewView: View {
    let markdown: String

    var body: some View {
        ScrollView {
            if let attr = try? AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(
                    allowsExtendedAttributes: true,
                    interpretedSyntax: .full
                )
            ) {
                Text(attr)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
            } else {
                Text(markdown)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
            }
        }
    }
}
