import SwiftUI

struct HotkeySettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    var appController: AppController?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Realtime ASR")
                        .font(.headline)
                    Text("Start/stop realtime streaming speech recognition")
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
                    Text("File ASR")
                        .font(.headline)
                    Text("Start/stop file-based speech recognition (record then transcribe)")
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
                Label("Keyboard Shortcuts", systemImage: "command")
                    .font(.headline)
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("How to set a shortcut")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    Text("Click the shortcut field, then press your desired key combination (e.g. \u{2325}Space). A modifier key (Option, Command, Control, or Shift) is required.")
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
