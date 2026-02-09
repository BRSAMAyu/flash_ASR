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
                Toggle("\u{542F}\u{52A8}\u{65F6}\u{81EA}\u{52A8}\u{6253}\u{5F00}\u{4E3B}\u{63A7}\u{5236}\u{53F0}", isOn: $settings.openDashboardOnLaunch)

                Toggle("\u{663E}\u{793A}\u{5F55}\u{97F3}\u{6307}\u{793A}\u{5668}", isOn: $settings.showRecordingIndicator)
                Toggle("\u{5F55}\u{97F3}\u{6307}\u{793A}\u{5668}\u{81EA}\u{52A8}\u{9690}\u{85CF}", isOn: $settings.recordingIndicatorAutoHide)
                Toggle("\u{4E3B}\u{63A7}\u{5236}\u{53F0} Markdown \u{9ED8}\u{8BA4}\u{9884}\u{89C8}", isOn: $settings.dashboardPreviewEnabled)
                Toggle("\u{60AC}\u{6D6E}\u{7A97} Markdown \u{9ED8}\u{8BA4}\u{9884}\u{89C8}", isOn: $settings.panelPreviewEnabled)

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

                Toggle("\u{4E8C}\u{6B21}\u{6587}\u{672C}\u{6E05}\u{6D17}\u{FF08}\u{53E3}\u{8BED}/\u{91CD}\u{590D}/\u{6807}\u{70B9}\u{FF09}", isOn: $settings.secondPassCleanupEnabled)
            } header: {
                Label("\u{884C}\u{4E3A}", systemImage: "slider.horizontal.3")
                    .font(.headline)
            }

            Section {
                Toggle("Markdown \u{6A21}\u{5F0F}", isOn: $settings.markdownModeEnabled)

                if settings.markdownModeEnabled {
                    Picker("AI \u{6A21}\u{5F0F}", selection: $settings.llmMode) {
                        Text("MiMo Flash").tag("mimo")
                        Text("GLM-4.7").tag("glm")
                        Text("\u{53CC}\u{5F15}\u{64CE}").tag("dual")
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 2) {
                        if settings.llmMode == "mimo" {
                            Text("MiMo Flash\u{FF1A}\u{5FEB}\u{901F}\u{751F}\u{6210}\u{FF0C}\u{9002}\u{5408}\u{65E5}\u{5E38}\u{4F7F}\u{7528}")
                        } else if settings.llmMode == "glm" {
                            Text("GLM-4.7\u{FF1A}\u{6DF1}\u{5EA6}\u{601D}\u{8003}\u{FF0C}\u{66F4}\u{9AD8}\u{8D28}\u{91CF}")
                        } else {
                            Text("\u{53CC}\u{5F15}\u{64CE}\u{FF1A}MiMo \u{5FEB}\u{901F}\u{51FA}\u{7ED3}\u{679C}\u{FF0C}GLM \u{540E}\u{53F0}\u{6DF1}\u{5EA6}\u{5904}\u{7406}")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Toggle("MiMo \u{601D}\u{8003}\u{6A21}\u{5F0F}", isOn: $settings.mimoThinkingEnabled)
                    Toggle("GLM \u{601D}\u{8003}\u{6A21}\u{5F0F}", isOn: $settings.glmThinkingEnabled)
                    Text("\u{9ED8}\u{8BA4}\u{4E24}\u{4E2A}\u{5747}\u{4E3A}\u{5173}\u{95ED}\u{3002}\u{5F00}\u{542F} GLM \u{601D}\u{8003}\u{7B49}\u{4EF7}\u{4E8E}\u{8BF7}\u{6C42}\u{4E0D}\u{53D1}\u{9001} thinking.disabled\u{3002}")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Picker("\u{9ED8}\u{8BA4}\u{6574}\u{7406}\u{7EA7}\u{522B}", selection: $settings.defaultMarkdownLevel) {
                        ForEach(MarkdownLevel.allCases, id: \.rawValue) { level in
                            Text(level.displayName).tag(level.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\u{5FE0}\u{5B9E}\u{FF1A}\u{4E0D}\u{6539}\u{539F}\u{6587}\u{FF0C}\u{53EA}\u{52A0} Markdown \u{683C}\u{5F0F}\u{7B26}\u{53F7}")
                        Text("\u{8F7B}\u{6DA6}\u{FF1A}\u{667A}\u{80FD}\u{8F6C}\u{5199}\u{FF0C}\u{6E05}\u{7406}\u{5E72}\u{6270}\u{8BCD}\u{FF0C}\u{4FE1}\u{606F}\u{4E0D}\u{4E22}\u{5931}")
                        Text("\u{6DF1}\u{6574}\u{FF1A}\u{8DDF}\u{968F}\u{7528}\u{6237}\u{601D}\u{7EF4}\u{FF0C}\u{9009}\u{62E9}\u{6700}\u{4F73} Markdown \u{5F62}\u{5F0F}")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Text("\u{5F00}\u{542F}\u{540E}\u{FF0C}\u{8F6C}\u{5199}\u{5B8C}\u{6210}\u{4F1A}\u{81EA}\u{52A8}\u{8C03}\u{7528} AI \u{5C06}\u{53E3}\u{8BED}\u{6574}\u{7406}\u{4E3A} Markdown \u{7B14}\u{8BB0}\u{FF0C}\u{7279}\u{522B}\u{9002}\u{5408}\u{5728} Obsidian \u{4E2D}\u{6784}\u{5EFA}\u{77E5}\u{8BC6}\u{5E93}\u{54E6}")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Label("Markdown \u{6574}\u{7406}", systemImage: "doc.richtext")
                    .font(.headline)
            }

            Section {
                HStack {
                    TextField("Vault \u{8DEF}\u{5F84}", text: $settings.obsidianVaultPath)
                        .textFieldStyle(.roundedBorder)
                    Button("\u{9009}\u{62E9}...") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        panel.message = "\u{9009}\u{62E9} Obsidian Vault \u{76EE}\u{5F55}"
                        if panel.runModal() == .OK, let url = panel.url {
                            settings.obsidianVaultPath = url.path
                        }
                    }
                }
                Text("\u{914D}\u{7F6E}\u{540E}\u{53EF}\u{5728}\u{5F55}\u{97F3}\u{7ED3}\u{679C}\u{9762}\u{677F}\u{4E2D}\u{4E00}\u{952E}\u{4FDD}\u{5B58} .md \u{6587}\u{4EF6}\u{5230}\u{6B64}\u{76EE}\u{5F55}")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Label("Obsidian", systemImage: "book.closed")
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
                    Label("\u{9EA6}\u{514B}\u{98CE}", systemImage: appState.permissions.microphone ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(appState.permissions.microphone ? .green : .red)
                    Spacer()
                    Text(appState.permissions.microphone ? "\u{5DF2}\u{6388}\u{6743}" : "\u{672A}\u{6388}\u{6743}")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("\u{8F85}\u{52A9}\u{529F}\u{80FD}", systemImage: appState.permissions.accessibility ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(appState.permissions.accessibility ? .green : .red)
                    Spacer()
                    Text(appState.permissions.accessibility ? "\u{5DF2}\u{6388}\u{6743}" : "\u{672A}\u{6388}\u{6743}")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("\u{8F93}\u{5165}\u{76D1}\u{542C}", systemImage: appState.permissions.inputMonitoring ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(appState.permissions.inputMonitoring ? .green : .red)
                    Spacer()
                    Text(appState.permissions.inputMonitoring ? "\u{5DF2}\u{6388}\u{6743}" : "\u{672A}\u{6388}\u{6743}")
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    Button("\u{6743}\u{9650}\u{5F15}\u{5BFC}") {
                        NotificationCenter.default.post(name: .openPermissionsGuide, object: nil)
                    }
                    Button("\u{9EA6}\u{514B}\u{98CE}") {
                        PermissionService.requestMicrophone { _ in
                            appController?.refreshPermissions(startup: false)
                        }
                    }
                    Button("\u{8F85}\u{52A9}\u{529F}\u{80FD}") {
                        PermissionService.requestAccessibilityPrompt()
                        PermissionService.openAccessibilitySettings()
                        appController?.refreshPermissions(startup: false)
                    }
                    Button("\u{8F93}\u{5165}\u{76D1}\u{542C}") {
                        PermissionService.requestInputMonitoringPrompt()
                        PermissionService.openInputMonitoringSettings()
                        appController?.refreshPermissions(startup: false)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                HStack(spacing: 8) {
                    Button("Finder") {
                        PermissionService.revealCurrentAppInFinder()
                    }
                    Button("\u{590D}\u{5236}\u{8DEF}\u{5F84}") {
                        PermissionService.copyCurrentAppPathToClipboard()
                    }
                    Button("\u{81EA}\u{68C0}\u{4FE1}\u{606F}") {
                        DiagnosticsService.copyPermissionSelfCheck(state: appState)
                    }
                    Button("\u{5237}\u{65B0}") {
                        appController?.refreshPermissions(startup: false)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Text(appState.serviceReady ? "\u{670D}\u{52A1}\u{5C31}\u{7EEA}\u{FF1A}\u{5FEB}\u{6377}\u{952E}\u{5DF2}\u{542F}\u{7528}" : "\u{670D}\u{52A1}\u{6682}\u{505C}\u{FF1A}\u{8BF7}\u{6388}\u{4E88}\u{6240}\u{6709}\u{6743}\u{9650}\u{4EE5}\u{542F}\u{7528}\u{5FEB}\u{6377}\u{952E}")
                    .font(.caption)
                    .foregroundColor(appState.serviceReady ? .green : .orange)

                Toggle("权限误检信任模式（已授权但检测失灵时使用）", isOn: $settings.permissionTrustOverride)
                    .onChange(of: settings.permissionTrustOverride) { _, _ in
                        appController?.refreshPermissions(startup: false)
                    }
                Text("如果权限页误判，可在“隐私与安全性”使用“-”删除 FlashASR 再重新添加授权。")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if !appState.permissions.inputMonitoring {
                    Text("\u{5982}\u{679C}\u{8F93}\u{5165}\u{76D1}\u{542C}\u{4E2D}\u{4ECD}\u{672A}\u{5217}\u{51FA} FlashASR\u{FF0C}\u{8BF7}\u{5C06}\u{5E94}\u{7528}\u{79FB}\u{52A8}\u{5230} /Applications \u{5E76}\u{91CD}\u{65B0}\u{542F}\u{52A8}\u{FF0C}\u{7136}\u{540E}\u{518D}\u{6B21}\u{70B9}\u{51FB}\u{6388}\u{6743}\u{8F93}\u{5165}\u{76D1}\u{542C}")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("\u{5F53}\u{524D}\u{5E94}\u{7528}\u{8DEF}\u{5F84}\u{FF1A}\(PermissionService.currentAppPathString())")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            } header: {
                Label("\u{6743}\u{9650}", systemImage: "lock.shield")
                    .font(.headline)
            }

            Section {
                HStack {
                    Text("\u{5B9E}\u{65F6}\u{8F6C}\u{5199}\u{5FEB}\u{6377}\u{952E}\u{51B2}\u{7A81}")
                    Spacer()
                    Text(appState.hotkeyConflictRealtime ? "\u{88AB}\u{7CFB}\u{7EDF}\u{5FEB}\u{6377}\u{952E}\u{5360}\u{7528}" : "OK")
                        .foregroundColor(appState.hotkeyConflictRealtime ? .orange : .green)
                }
                HStack {
                    Text("\u{5F55}\u{97F3}\u{8F6C}\u{5199}\u{5FEB}\u{6377}\u{952E}\u{51B2}\u{7A81}")
                    Spacer()
                    Text(appState.hotkeyConflictFile ? "\u{88AB}\u{7CFB}\u{7EDF}\u{5FEB}\u{6377}\u{952E}\u{5360}\u{7528}" : "OK")
                        .foregroundColor(appState.hotkeyConflictFile ? .orange : .green)
                }
                Button("\u{91CD}\u{65B0}\u{68C0}\u{67E5}\u{5FEB}\u{6377}\u{952E}\u{51B2}\u{7A81}") {
                    appController?.refreshPermissions(startup: false)
                }
                .buttonStyle(.bordered)
            } header: {
                Label("\u{5FEB}\u{6377}\u{952E}\u{72B6}\u{6001}", systemImage: "exclamationmark.triangle")
                    .font(.headline)
            }

            Section {
                Button("\u{91CD}\u{65B0}\u{6253}\u{5F00}\u{65B0}\u{624B}\u{5F15}\u{5BFC}") {
                    NotificationCenter.default.post(name: .openOnboarding, object: nil)
                }
                .buttonStyle(.bordered)
                Button("\u{5BFC}\u{51FA}\u{8BCA}\u{65AD}\u{4FE1}\u{606F}") {
                    NotificationCenter.default.post(name: .exportDiagnostics, object: nil)
                }
                .buttonStyle(.borderedProminent)
                Text("\u{5982}\u{679C}\u{9700}\u{8981}\u{91CD}\u{65B0}\u{8FDB}\u{884C}\u{5F15}\u{5BFC}\u{8BBE}\u{7F6E}\u{FF0C}\u{8BF7}\u{70B9}\u{51FB}\u{4E0A}\u{65B9}\u{6309}\u{94AE}")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Label("\u{65B0}\u{624B}\u{5F15}\u{5BFC}", systemImage: "sparkles")
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
