import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    var appController: AppController?
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var appState: AppStatePublisher

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
                Toggle("\u{5F55}\u{97F3}\u{6307}\u{793A}\u{5668}\u{81EA}\u{52A8}\u{9690}\u{85CF}", isOn: $settings.recordingIndicatorAutoHide)

                Toggle("\u{6807}\u{70B9}\u{7A33}\u{6001}\u{6A21}\u{5F0F} (partial \u{9632}\u{6296})", isOn: $settings.punctuationStabilizationEnabled)
                if settings.punctuationStabilizationEnabled {
                    HStack {
                        Text("\u{7A33}\u{6001}\u{5EF6}\u{8FDF}")
                        Spacer()
                        Text("\(Int(settings.punctuationStabilizationDelayMs)) ms")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.punctuationStabilizationDelayMs, in: 200...400, step: 20)
                }

                Toggle("二次文本清洗（口语/重复/标点）", isOn: $settings.secondPassCleanupEnabled)
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

            Section {
                HStack {
                    Label("Microphone", systemImage: appState.permissions.microphone ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(appState.permissions.microphone ? .green : .red)
                    Spacer()
                    Text(appState.permissions.microphone ? "Granted" : "Missing")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("Accessibility", systemImage: appState.permissions.accessibility ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(appState.permissions.accessibility ? .green : .red)
                    Spacer()
                    Text(appState.permissions.accessibility ? "Granted" : "Missing")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("Input Monitoring", systemImage: appState.permissions.inputMonitoring ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(appState.permissions.inputMonitoring ? .green : .red)
                    Spacer()
                    Text(appState.permissions.inputMonitoring ? "Granted" : "Missing")
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 10) {
                    Button("Open Permissions Guide") {
                        NotificationCenter.default.post(name: .openPermissionsGuide, object: nil)
                    }
                    Button("Grant Mic") {
                        PermissionService.requestMicrophone { _ in
                            appController?.refreshPermissions(startup: false)
                        }
                    }
                    Button("Grant Accessibility") {
                        PermissionService.requestAccessibilityPrompt()
                        PermissionService.openAccessibilitySettings()
                        appController?.refreshPermissions(startup: false)
                    }
                    Button("Grant Input Monitoring") {
                        PermissionService.requestInputMonitoringPrompt()
                        PermissionService.openInputMonitoringSettings()
                        appController?.refreshPermissions(startup: false)
                    }
                    Button("Reveal App in Finder") {
                        PermissionService.revealCurrentAppInFinder()
                    }
                    Button("Copy App Path") {
                        PermissionService.copyCurrentAppPathToClipboard()
                    }
                    Button("Refresh") {
                        appController?.refreshPermissions(startup: false)
                    }
                    Button("Copy Self-Check") {
                        DiagnosticsService.copyPermissionSelfCheck(state: appState)
                    }
                }
                .buttonStyle(.bordered)

                Text(appState.serviceReady ? "Service ready: hotkeys enabled" : "Service paused: grant all permissions to enable hotkeys")
                    .font(.caption)
                    .foregroundColor(appState.serviceReady ? .green : .orange)

                if !appState.permissions.inputMonitoring {
                    Text("If Input Monitoring still doesn't list FlashASR, move the app to /Applications and relaunch, then click Grant Input Monitoring again.")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("Current app path: \(PermissionService.currentAppPathString())")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            } header: {
                Label("Permissions", systemImage: "lock.shield")
                    .font(.headline)
            }

            Section {
                HStack {
                    Text("Realtime Hotkey Conflict")
                    Spacer()
                    Text(appState.hotkeyConflictRealtime ? "被系统快捷键占用" : "OK")
                        .foregroundColor(appState.hotkeyConflictRealtime ? .orange : .green)
                }
                HStack {
                    Text("File Hotkey Conflict")
                    Spacer()
                    Text(appState.hotkeyConflictFile ? "被系统快捷键占用" : "OK")
                        .foregroundColor(appState.hotkeyConflictFile ? .orange : .green)
                }
                Button("Recheck Hotkey Conflicts") {
                    appController?.refreshPermissions(startup: false)
                }
                .buttonStyle(.bordered)
            } header: {
                Label("Hotkey Health", systemImage: "exclamationmark.triangle")
                    .font(.headline)
            }

            Section {
                Button("Reopen Onboarding") {
                    NotificationCenter.default.post(name: .openOnboarding, object: nil)
                }
                .buttonStyle(.bordered)
                Button("Export Diagnostic Bundle") {
                    NotificationCenter.default.post(name: .exportDiagnostics, object: nil)
                }
                .buttonStyle(.borderedProminent)
                Text("Use this if you want to run the full guided setup flow again.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Label("Onboarding", systemImage: "sparkles")
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
