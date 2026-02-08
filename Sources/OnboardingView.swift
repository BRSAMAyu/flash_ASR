import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var settings: SettingsManager
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            // Step indicators
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i <= step ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Content
            Group {
                switch step {
                case 0: welcomeStep
                case 1: apiKeyStep
                case 2: permissionsStep
                case 3: hotkeysStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Spacer()
        }
        .frame(width: 460, height: 400)
        .padding()
    }

    // MARK: - Step 0: Welcome
    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(
                    .linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Welcome to FlashASR")
                .font(.title)
                .fontWeight(.bold)

            Text("Fast speech-to-text powered by Alibaba Dashscope.\nTranscribe your voice in real-time or record and convert.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            Spacer()

            Button("Get Started") { step = 1 }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    // MARK: - Step 1: API Key
    private var apiKeyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text("API Key")
                .font(.title2)
                .fontWeight(.bold)

            Text("FlashASR uses Alibaba Dashscope for speech recognition.\nA default key is provided, or enter your own.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("API Key")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("sk-...", text: $settings.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 340)
            }
            .padding(.top, 8)

            Link(destination: URL(string: "https://dashscope.console.aliyun.com/")!) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Get your own API Key")
                }
                .font(.caption)
            }

            Spacer()

            HStack {
                Button("Back") { step = 0 }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Next") { step = 2 }
                    .buttonStyle(.borderedProminent)
                    .disabled(settings.apiKey.isEmpty)
            }
            .frame(maxWidth: 340)
        }
    }

    // MARK: - Step 2: Permissions
    private var permissionsStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundColor(.green)

            Text("Permissions")
                .font(.title2)
                .fontWeight(.bold)

            Text("FlashASR needs a few permissions to work properly.")
                .foregroundColor(.secondary)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 12) {
                permissionRow(
                    icon: "mic.fill",
                    color: .red,
                    title: "Microphone",
                    desc: "Required for capturing your voice"
                )
                permissionRow(
                    icon: "hand.raised.fill",
                    color: .blue,
                    title: "Accessibility",
                    desc: "Required for typing text into apps"
                )
                permissionRow(
                    icon: "keyboard",
                    color: .purple,
                    title: "Input Monitoring",
                    desc: "Required for global keyboard shortcuts"
                )
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.1)))
            .frame(maxWidth: 360)

            Text("You'll be prompted to grant these when needed.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            HStack {
                Button("Back") { step = 1 }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Next") { step = 3 }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: 340)
        }
    }

    // MARK: - Step 3: Hotkeys
    private var hotkeysStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 40))
                .foregroundColor(.purple)

            Text("Keyboard Shortcuts")
                .font(.title2)
                .fontWeight(.bold)

            Text("Use these shortcuts from anywhere on your Mac.")
                .foregroundColor(.secondary)
                .font(.subheadline)

            VStack(spacing: 12) {
                hotkeyRow(
                    label: "Realtime ASR",
                    shortcut: settings.realtimeHotkeyDisplay(),
                    desc: "Stream speech to text in real-time"
                )
                hotkeyRow(
                    label: "File ASR",
                    shortcut: settings.fileHotkeyDisplay(),
                    desc: "Record audio, then transcribe"
                )
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.1)))
            .frame(maxWidth: 360)

            Text("You can change these in Settings > Hotkeys.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            HStack {
                Button("Back") { step = 2 }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Done") {
                    settings.hasCompletedOnboarding = true
                    // Close the onboarding window
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: 340)
        }
    }

    // MARK: - Helpers

    private func permissionRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func hotkeyRow(label: String, shortcut: String, desc: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(shortcut)
                .font(.system(size: 14, design: .rounded))
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.15))
                )
        }
    }
}
