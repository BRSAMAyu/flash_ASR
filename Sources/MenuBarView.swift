import SwiftUI
import AppKit

struct MenuBarLabel: View {
    @ObservedObject var appState: AppStatePublisher

    var body: some View {
        if !appState.serviceReady {
            Text("ASR!")
                .font(.system(size: 12, weight: .bold))
        } else {
        switch appState.state {
        case .idle:
            Image(systemName: "waveform")
        case .listening:
            Image(systemName: "waveform.badge.mic")
        case .stopping:
            Image(systemName: "waveform.badge.ellipsis")
        }
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var appState: AppStatePublisher
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        Group {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
            }
            .disabled(true)

            Divider()

            if appState.state == .idle {
                Button("\u{5B9E}\u{65F6}\u{8F6C}\u{5199}  \(settings.realtimeHotkeyDisplay())") {
                    NotificationCenter.default.post(name: .triggerRealtime, object: nil)
                }
                Button("\u{5F55}\u{97F3}\u{8F6C}\u{5199}  \(settings.fileHotkeyDisplay())") {
                    NotificationCenter.default.post(name: .triggerFile, object: nil)
                }
            } else {
                Button("\u{505C}\u{6B62}") {
                    if appState.mode == .realtime {
                        NotificationCenter.default.post(name: .triggerRealtime, object: nil)
                    } else {
                        NotificationCenter.default.post(name: .triggerFile, object: nil)
                    }
                }
            }

            if !appState.lastFinalText.isEmpty && appState.state == .idle {
                Divider()
                let preview = String(appState.lastFinalText.prefix(60))
                Text(preview + (appState.lastFinalText.count > 60 ? "..." : ""))
                    .font(.caption)
                    .lineLimit(2)
                Button("\u{590D}\u{5236}\u{4E0A}\u{6B21}\u{7ED3}\u{679C}") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(appState.lastFinalText, forType: .string)
                }
            }

            Divider()

            Toggle("Markdown \u{6A21}\u{5F0F}", isOn: $settings.markdownModeEnabled)

            if settings.markdownModeEnabled {
                Picker("\u{9ED8}\u{8BA4}\u{7EA7}\u{522B}", selection: $settings.defaultMarkdownLevel) {
                    Text("\u{5FE0}\u{5B9E}").tag(0)
                    Text("\u{8F7B}\u{6DA6}").tag(1)
                    Text("\u{6DF1}\u{6574}").tag(2)
                }
            }

            if !SessionManager.shared.sessions.isEmpty {
                Menu("\u{5386}\u{53F2}\u{4F1A}\u{8BDD}") {
                    ForEach(SessionManager.shared.sessions) { session in
                        Button("\(session.title.isEmpty ? "\u{672A}\u{547D}\u{540D}" : session.title) (\(session.rounds.count)\u{8F6E})") {
                            NotificationCenter.default.post(name: .openSession, object: nil, userInfo: ["id": session.id.uuidString])
                        }
                    }
                }
            }

            Divider()

            if !appState.serviceReady {
                Button("\u{6253}\u{5F00}\u{6743}\u{9650}\u{5F15}\u{5BFC}") {
                    NotificationCenter.default.post(name: .openPermissionsGuide, object: nil)
                }
                Button("\u{590D}\u{5236}\u{6743}\u{9650}\u{81EA}\u{68C0}\u{4FE1}\u{606F}") {
                    NotificationCenter.default.post(name: .copyPermissionSelfCheck, object: nil)
                }
            }

            SettingsLink {
                Text("\u{8BBE}\u{7F6E}...")
            }

            Button("\u{91CD}\u{65B0}\u{6253}\u{5F00}\u{65B0}\u{624B}\u{5F15}\u{5BFC}") {
                NotificationCenter.default.post(name: .openOnboarding, object: nil)
            }
            Button("\u{5BFC}\u{51FA}\u{8BCA}\u{65AD}\u{4FE1}\u{606F}") {
                NotificationCenter.default.post(name: .exportDiagnostics, object: nil)
            }
            Button("\u{91CD}\u{8BD5}\u{5931}\u{8D25}\u{7684}\u{6587}\u{4EF6}\u{4E0A}\u{4F20}") {
                NotificationCenter.default.post(name: .retryFailedFileUpload, object: nil)
            }

            Divider()

            Button("\u{9000}\u{51FA} FlashASR") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    var statusColor: Color {
        if !appState.serviceReady { return .orange }
        switch appState.state {
        case .idle: return .gray
        case .listening: return .red
        case .stopping: return .orange
        }
    }

    var statusText: String {
        if !appState.serviceReady {
            return "\u{6743}\u{9650}\u{672A}\u{5C31}\u{7EEA}"
        }
        switch appState.state {
        case .idle: return "\u{5C31}\u{7EEA}"
        case .listening:
            return appState.mode == .realtime ? "\u{6B63}\u{5728}\u{542C}\u{FF08}\u{5B9E}\u{65F6}\u{FF09}" : "\u{6B63}\u{5728}\u{5F55}\u{97F3}..."
        case .stopping: return "\u{5904}\u{7406}\u{4E2D}..."
        }
    }
}

extension Notification.Name {
    static let triggerRealtime = Notification.Name("FlashASR.triggerRealtime")
    static let triggerFile = Notification.Name("FlashASR.triggerFile")
    static let openPermissionsGuide = Notification.Name("FlashASR.openPermissionsGuide")
    static let openOnboarding = Notification.Name("FlashASR.openOnboarding")
    static let copyPermissionSelfCheck = Notification.Name("FlashASR.copyPermissionSelfCheck")
    static let exportDiagnostics = Notification.Name("FlashASR.exportDiagnostics")
    static let retryFailedFileUpload = Notification.Name("FlashASR.retryFailedFileUpload")
    // v4
    static let continueRecording = Notification.Name("FlashASR.continueRecording")
    static let saveToObsidian = Notification.Name("FlashASR.saveToObsidian")
    static let fullRefinement = Notification.Name("FlashASR.fullRefinement")
    static let switchMarkdownLevel = Notification.Name("FlashASR.switchMarkdownLevel")
    static let openSession = Notification.Name("FlashASR.openSession")
}
