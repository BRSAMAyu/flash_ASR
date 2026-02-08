import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsManager

    private let languages: [(String, String)] = [
        ("zh", "\u{4E2D}\u{6587}"),
        ("en", "English"),
        ("ja", "\u{65E5}\u{672C}\u{8A9E}"),
        ("ko", "\u{D55C}\u{AD6D}\u{C5B4}"),
        ("auto", "\u{81EA}\u{52A8}\u{68C0}\u{6D4B}")
    ]

    var body: some View {
        Form {
            Section {
                Picker("\u{8BC6}\u{522B}\u{8BED}\u{8A00}", selection: $settings.language) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Label("\u{8BED}\u{8A00}", systemImage: "globe")
                    .font(.headline)
            }

            Section {
                Toggle("\u{9759}\u{97F3}\u{540E}\u{81EA}\u{52A8}\u{505C}\u{6B62}", isOn: $settings.autoStopEnabled)

                if settings.autoStopEnabled {
                    HStack {
                        Text("\u{9759}\u{97F3}\u{7B49}\u{5F85}\u{65F6}\u{95F4}")
                        Spacer()
                        Text(String(format: "%.1f\u{79D2}", settings.autoStopDelay))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.autoStopDelay, in: 1.0...5.0, step: 0.1)
                }

                Toggle("\u{5B9E}\u{65F6}\u{6A21}\u{5F0F}\u{76F4}\u{63A5}\u{8F93}\u{5165}\u{5230}\u{5F53}\u{524D} App", isOn: $settings.realtimeTypeEnabled)

                Toggle("\u{663E}\u{793A}\u{5F55}\u{97F3}\u{6307}\u{793A}\u{5668}", isOn: $settings.showRecordingIndicator)
            } header: {
                Label("\u{884C}\u{4E3A}", systemImage: "slider.horizontal.3")
                    .font(.headline)
            }

            Section {
                Toggle("\u{5F00}\u{673A}\u{81EA}\u{52A8}\u{542F}\u{52A8}", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, newValue in
                        configureLaunchAtLogin(newValue)
                    }
            } header: {
                Label("\u{7CFB}\u{7EDF}", systemImage: "laptopcomputer")
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
