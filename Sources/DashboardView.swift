import SwiftUI
import AppKit

struct DashboardView: View {
    @EnvironmentObject var appState: AppStatePublisher
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("FlashASR 控制台")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                if appState.state == .idle {
                    Button("开始实时转写") {
                        NotificationCenter.default.post(name: .triggerRealtime, object: nil)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("开始录音转写") {
                        NotificationCenter.default.post(name: .triggerFile, object: nil)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("停止") {
                        if appState.mode == .realtime {
                            NotificationCenter.default.post(name: .triggerRealtime, object: nil)
                        } else {
                            NotificationCenter.default.post(name: .triggerFile, object: nil)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()

                Button("权限引导") {
                    NotificationCenter.default.post(name: .openPermissionsGuide, object: nil)
                }
                .buttonStyle(.bordered)
                Button("新手引导") {
                    NotificationCenter.default.post(name: .openOnboarding, object: nil)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            HStack {
                Text("最近结果")
                    .font(.headline)
                Spacer()
                Button("复制") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(contentText, forType: .string)
                }
                .buttonStyle(.bordered)
                .disabled(contentText.isEmpty)
            }

            HStack {
                Toggle("Markdown 预览", isOn: $settings.dashboardPreviewEnabled)
                Spacer()
                if settings.markdownModeEnabled {
                    Picker("层级", selection: $settings.defaultMarkdownLevel) {
                        Text("忠实").tag(0)
                        Text("轻润").tag(1)
                        Text("深整").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }

            GroupBox {
                if settings.dashboardPreviewEnabled && !contentText.isEmpty {
                    MarkdownPreviewView(markdown: contentText)
                        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    ScrollView {
                        Text(contentText.isEmpty ? "暂无内容" : contentText)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity, alignment: .topLeading)
                }
            }

            HStack {
                Button("文本整理（剪贴板）") {
                    NotificationCenter.default.post(name: .processClipboardText, object: nil)
                }
                .buttonStyle(.bordered)
                Button("文本整理（文件）") {
                    NotificationCenter.default.post(name: .processFileText, object: nil)
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("设置") {
                    NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(minWidth: 640, minHeight: 460)
    }

    private var contentText: String {
        if settings.markdownModeEnabled && !appState.markdownText.isEmpty {
            return appState.markdownText
        }
        if let session = appState.currentSession {
            return session.allOriginalText
        }
        if !appState.lastFinalText.isEmpty {
            return appState.lastFinalText
        }
        return appState.currentTranscript
    }

    private var statusText: String {
        if !appState.serviceReady {
            return "权限未就绪"
        }
        switch appState.state {
        case .idle: return "就绪"
        case .listening: return appState.mode == .realtime ? "实时转写中" : "录音中"
        case .stopping: return "处理中"
        }
    }
}
