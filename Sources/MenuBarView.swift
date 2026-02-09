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

            if !appState.serviceReady {
                Button("Open Permissions Guide") {
                    NotificationCenter.default.post(name: .openPermissionsGuide, object: nil)
                }
                Button("Copy Permission Self-Check") {
                    NotificationCenter.default.post(name: .copyPermissionSelfCheck, object: nil)
                }
            }

            SettingsLink {
                Text("\u{8BBE}\u{7F6E}...")
            }

            Button("\u{91CD}\u{65B0}\u{6253}\u{5F00}\u{65B0}\u{624B}\u{5F15}\u{5BFC}") {
                NotificationCenter.default.post(name: .openOnboarding, object: nil)
            }
            Button("Export Diagnostic Bundle") {
                NotificationCenter.default.post(name: .exportDiagnostics, object: nil)
            }
            Button("Retry Failed File Upload") {
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
}
