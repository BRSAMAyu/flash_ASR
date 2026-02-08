import SwiftUI

struct AboutView: View {
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
    private let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // App icon
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    .linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 6) {
                Text("FlashASR")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Fast speech-to-text for macOS")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Version \(version) (\(build))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()
                .frame(maxWidth: 200)

            VStack(spacing: 8) {
                Text("Powered by Alibaba Dashscope ASR")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Link(destination: URL(string: "https://github.com/user/FlashASR")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text("GitHub Repository")
                    }
                    .font(.caption)
                }
            }

            Spacer()

            Text("\u{00A9} 2025 FlashASR")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
