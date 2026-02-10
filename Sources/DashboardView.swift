import SwiftUI
import AppKit

struct DashboardView: View {
    @EnvironmentObject var appState: AppStatePublisher
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        HSplitView {
            SessionSidebarView()
                .environmentObject(appState)
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)

            VStack(alignment: .leading, spacing: 10) {
                headerBar
                modeTabs
                actionBar
                editorAndPreview
                footerBar
            }
            .padding(14)
        }
        .frame(minWidth: 960, minHeight: 560)
        .onAppear {
            if appState.editableText.isEmpty {
                appState.editableText = displayText
            }
        }
        .onChange(of: appState.selectedTab) { _, _ in
            let text = displayText
            if !text.isEmpty {
                appState.editableText = text
            }
        }
        .onChange(of: appState.currentSession?.id) { _, _ in
            let text = displayText
            if !text.isEmpty {
                appState.editableText = text
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Text("FlashASR 控制台")
                .font(.title3)
                .fontWeight(.semibold)
            Spacer()
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var modeTabs: some View {
        HStack(spacing: 8) {
            ForEach(MarkdownTab.allCases, id: \.rawValue) { tab in
                Button(tab.displayName) {
                    if tab == .original {
                        appState.selectedTab = .original
                    } else if let level = tab.markdownLevel {
                        appState.selectedTab = tab
                        NotificationCenter.default.post(name: .switchMarkdownLevel, object: nil, userInfo: ["level": level.rawValue])
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.selectedTab == tab ? .pink : .gray)
                .controlSize(.small)
            }
            Spacer()
            Toggle("预览", isOn: $settings.dashboardPreviewEnabled)
                .toggleStyle(.switch)
                .frame(width: 130)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            if appState.state == .idle {
                Button("实时") { NotificationCenter.default.post(name: .triggerRealtime, object: nil) }
                    .buttonStyle(.borderedProminent)
                Button("录音") { NotificationCenter.default.post(name: .triggerFile, object: nil) }
                    .buttonStyle(.bordered)
                Button("继续录音") {
                    NotificationCenter.default.post(name: .continueRecording, object: nil, userInfo: ["mode": 0])
                }
                .buttonStyle(.bordered)
                .disabled(appState.currentSession == nil)
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

            Divider().frame(height: 20)

            Button("\u{590D}\u{5236}") {
                let text = displayText
                let isMarkdown = appState.selectedTab != .original
                if isMarkdown {
                    RichClipboard.shared.writeMultiFormat(markdown: text)
                } else {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                }
            }
            .buttonStyle(.bordered)
            .disabled(displayText.isEmpty)

            Menu("\u{5BFC}\u{51FA}") {
                if !settings.obsidianVaultPath.isEmpty {
                    Button("Obsidian") {
                        NotificationCenter.default.post(name: .saveToObsidian, object: nil)
                    }
                    Divider()
                }
                ForEach(ExportFormat.allCases, id: \.rawValue) { format in
                    Button(format.displayName) {
                        NotificationCenter.default.post(name: .exportSession, object: nil, userInfo: ["format": format.rawValue])
                    }
                }
            }
            .disabled(appState.currentSession == nil)

            Button("全文") {
                let level = appState.selectedTab.markdownLevel ?? (MarkdownLevel(rawValue: settings.defaultMarkdownLevel) ?? .light)
                NotificationCenter.default.post(name: .fullRefinement, object: nil, userInfo: ["level": level.rawValue])
            }
            .buttonStyle(.bordered)
            .disabled(appState.currentSession == nil || (appState.currentSession?.rounds.count ?? 0) < 2)

            Spacer()

            Button("设置") { NotificationCenter.default.post(name: .openSettingsWindow, object: nil) }
                .buttonStyle(.bordered)
            Button("权限") { NotificationCenter.default.post(name: .openPermissionsGuide, object: nil) }
                .buttonStyle(.bordered)
        }
    }

    private var editorAndPreview: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("可编辑文本")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $appState.editableText)
                    .font(.system(size: 13))
                    .frame(minHeight: 320)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.25), lineWidth: 1))
                HStack(spacing: 8) {
                    Button("开始转写") {
                        let level = appState.selectedTab.markdownLevel ?? (MarkdownLevel(rawValue: settings.defaultMarkdownLevel) ?? .light)
                        NotificationCenter.default.post(name: .processManualText, object: nil, userInfo: ["text": appState.editableText, "level": level.rawValue])
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.editableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.markdownProcessing)
                    Button("撤回转写") {
                        NotificationCenter.default.post(name: .undoTransform, object: nil)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!appState.canUndoTransform)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text(settings.dashboardPreviewEnabled ? "Markdown 预览" : "输出文本")
                    .font(.caption)
                    .foregroundColor(.secondary)
                GroupBox {
                    if settings.dashboardPreviewEnabled && !displayText.isEmpty {
                        MarkdownPreviewView(markdown: displayText)
                            .frame(maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            Text(displayText.isEmpty ? "暂无内容" : displayText)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var footerBar: some View {
        HStack {
            Button("文本整理（剪贴板）") { NotificationCenter.default.post(name: .processClipboardText, object: nil) }
                .buttonStyle(.bordered)
            Button("文本整理（文件）") { NotificationCenter.default.post(name: .processFileText, object: nil) }
                .buttonStyle(.bordered)
            Spacer()
            if appState.markdownProcessing {
                ProgressView().scaleEffect(0.8)
                Text("整理中...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var displayText: String {
        DisplayTextResolver.resolve(appState: appState, selectedTab: appState.selectedTab, showGLMVersion: appState.showGLMVersion)
    }

    private var statusText: String {
        if !appState.serviceReady { return "权限未就绪" }
        switch appState.state {
        case .idle: return "就绪"
        case .listening: return appState.mode == .realtime ? "实时转写中" : "录音中"
        case .stopping: return "处理中"
        }
    }
}
