import SwiftUI
import AppKit

struct MenuBarLabel: View {
    @ObservedObject var appState: AppStatePublisher

    var body: some View {
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

struct MenuBarView: View {
    @EnvironmentObject var appState: AppStatePublisher
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        Group {
            // Status
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
            }
            .disabled(true)

            Divider()

            // Actions
            if appState.state == .idle {
                Button("Start Realtime ASR  \(settings.realtimeHotkeyDisplay())") {
                    NotificationCenter.default.post(name: .triggerRealtime, object: nil)
                }
                Button("Start File ASR  \(settings.fileHotkeyDisplay())") {
                    NotificationCenter.default.post(name: .triggerFile, object: nil)
                }
            } else {
                Button("Stop") {
                    if appState.mode == .realtime {
                        NotificationCenter.default.post(name: .triggerRealtime, object: nil)
                    } else {
                        NotificationCenter.default.post(name: .triggerFile, object: nil)
                    }
                }
            }

            // Last transcript
            if !appState.lastFinalText.isEmpty && appState.state == .idle {
                Divider()
                let preview = String(appState.lastFinalText.prefix(60))
                Text(preview + (appState.lastFinalText.count > 60 ? "..." : ""))
                    .font(.caption)
                    .lineLimit(2)
                Button("Copy Last Result") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(appState.lastFinalText, forType: .string)
                }
            }

            Divider()

            SettingsLink {
                Text("Settings...")
            }

            Divider()

            Button("Quit FlashASR") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    var statusColor: Color {
        switch appState.state {
        case .idle: return .gray
        case .listening: return .red
        case .stopping: return .orange
        }
    }

    var statusText: String {
        switch appState.state {
        case .idle: return "Ready"
        case .listening:
            return appState.mode == .realtime ? "Listening (Realtime)" : "Recording (File)"
        case .stopping: return "Processing..."
        }
    }
}

// Notification names for menu -> AppController communication
extension Notification.Name {
    static let triggerRealtime = Notification.Name("FlashASR.triggerRealtime")
    static let triggerFile = Notification.Name("FlashASR.triggerFile")
}
