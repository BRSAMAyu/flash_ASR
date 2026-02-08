import SwiftUI

struct HotkeySettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    var appController: AppController?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\u{5B9E}\u{65F6}\u{8F6C}\u{5199}")
                        .font(.headline)
                    Text("\u{5F00}\u{59CB}/\u{505C}\u{6B62}\u{5B9E}\u{65F6}\u{8BED}\u{97F3}\u{8F6C}\u{6587}\u{5B57}")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HotkeyRecorderView(
                        keyCode: $settings.realtimeHotkeyCode,
                        modifiers: $settings.realtimeHotkeyModifiers,
                        displayString: settings.realtimeHotkeyDisplay(),
                        onStartRecording: { appController?.pauseHotkeys() },
                        onStopRecording: { appController?.resumeHotkeys() }
                    )
                    .frame(width: 160, height: 28)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("\u{5F55}\u{97F3}\u{8F6C}\u{5199}")
                        .font(.headline)
                    Text("\u{5F00}\u{59CB}/\u{505C}\u{6B62}\u{5F55}\u{97F3}\u{FF0C}\u{5F55}\u{5B8C}\u{540E}\u{81EA}\u{52A8}\u{8F6C}\u{6587}\u{5B57}")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HotkeyRecorderView(
                        keyCode: $settings.fileHotkeyCode,
                        modifiers: $settings.fileHotkeyModifiers,
                        displayString: settings.fileHotkeyDisplay(),
                        onStartRecording: { appController?.pauseHotkeys() },
                        onStopRecording: { appController?.resumeHotkeys() }
                    )
                    .frame(width: 160, height: 28)
                }
                .padding(.vertical, 4)
            } header: {
                Label("\u{5FEB}\u{6377}\u{952E}", systemImage: "command")
                    .font(.headline)
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("\u{5982}\u{4F55}\u{8BBE}\u{7F6E}\u{5FEB}\u{6377}\u{952E}")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    Text("\u{70B9}\u{51FB}\u{5FEB}\u{6377}\u{952E}\u{6846}\u{FF0C}\u{7136}\u{540E}\u{6309}\u{4E0B}\u{4F60}\u{60F3}\u{8981}\u{7684}\u{7EC4}\u{5408}\u{952E}\u{3002}\u{9700}\u{8981}\u{4FEE}\u{9970}\u{952E}\u{54E6}\u{FF5E}")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
