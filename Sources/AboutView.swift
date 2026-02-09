import SwiftUI

struct AboutView: View {
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "5.0.0"
    private let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .pink.opacity(0.3), radius: 6, y: 3)

            VStack(spacing: 6) {
                Text("FlashASR")
                    .font(.title)
                    .fontWeight(.bold)

                Text("\u{8D85}\u{5FEB}\u{7684}\u{8BED}\u{97F3}\u{8F6C}\u{6587}\u{5B57}\u{5C0F}\u{52A9}\u{624B} \u{2728}")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("v\(version) (\(build))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()
                .frame(maxWidth: 200)

            VStack(spacing: 8) {
                Text("\u{7531} BRSAMA \u{5F00}\u{53D1}")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("\u{8BED}\u{97F3}\u{8BC6}\u{522B}\u{7531}\u{963F}\u{91CC} Dashscope \u{63D0}\u{4F9B}\u{652F}\u{6301}")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("\u{5FAE}\u{4FE1}\u{8054}\u{7CFB}\u{FF1A}BR_SAMA")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\u{53CB}\u{60C5}\u{8D5E}\u{52A9} / \u{95EE}\u{9898}\u{53CD}\u{9988} / \u{6539}\u{8FDB}\u{5EFA}\u{8BAE}\u{6B22}\u{8FCE}\u{901A}\u{8FC7}\u{5FAE}\u{4FE1}\u{8054}\u{7CFB}")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Link(destination: URL(string: "https://github.com/BRSAMAyu/flash_ASR")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text("GitHub \u{9879}\u{76EE}\u{4E3B}\u{9875}")
                    }
                    .font(.caption)
                }
            }

            Spacer()

            Text("\u{00A9} 2025 BRSAMA")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
