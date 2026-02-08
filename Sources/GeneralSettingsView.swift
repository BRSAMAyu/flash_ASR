import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsManager

    private let languages: [(String, String)] = [
        ("zh", "Chinese / \u{4E2D}\u{6587}"),
        ("en", "English"),
        ("ja", "Japanese / \u{65E5}\u{672C}\u{8A9E}"),
        ("ko", "Korean / \u{D55C}\u{AD6D}\u{C5B4}"),
        ("auto", "Auto Detect")
    ]

    var body: some View {
        Form {
            Section {
                Picker("Recognition Language", selection: $settings.language) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Label("Language", systemImage: "globe")
                    .font(.headline)
            }

            Section {
                Toggle("Auto-stop after silence", isOn: $settings.autoStopEnabled)

                if settings.autoStopEnabled {
                    HStack {
                        Text("Silence delay")
                        Spacer()
                        Text(String(format: "%.1fs", settings.autoStopDelay))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.autoStopDelay, in: 1.0...5.0, step: 0.1)
                }

                Toggle("Type into focused app (realtime mode)", isOn: $settings.realtimeTypeEnabled)

                Toggle("Show recording indicator", isOn: $settings.showRecordingIndicator)
            } header: {
                Label("Behavior", systemImage: "slider.horizontal.3")
                    .font(.headline)
            }

            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, newValue in
                        configureLaunchAtLogin(newValue)
                    }
            } header: {
                Label("System", systemImage: "laptopcomputer")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func configureLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Console.line("Launch at login error: \(error)")
            }
        }
    }
}
