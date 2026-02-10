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
        .sheet(isPresented: $appState.showCourseProfileSheet) {
            CourseProfileSheet()
                .environmentObject(appState)
        }
        .onAppear {
            if appState.editableText.isEmpty {
                appState.editableText = displayText
            }
        }
        .onChange(of: appState.selectedTab) { _, _ in
            appState.lectureNoteMode = .transcript
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
        .onChange(of: appState.lectureNoteMode) { _, _ in
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
            if appState.currentSession?.kind == .lecture {
                Picker("", selection: $appState.lectureNoteMode) {
                    Text(LectureNoteMode.transcript.displayName).tag(LectureNoteMode.transcript)
                    Text(LectureNoteMode.lessonPlan.displayName).tag(LectureNoteMode.lessonPlan)
                    Text(LectureNoteMode.review.displayName).tag(LectureNoteMode.review)
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            } else {
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
                if appState.currentSession != nil {
                    Picker("", selection: $appState.lectureNoteMode) {
                        Text("常规").tag(LectureNoteMode.transcript)
                        Text("教案").tag(LectureNoteMode.lessonPlan)
                        Text("复习").tag(LectureNoteMode.review)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
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
                if appState.lectureRecordingActive {
                    Button("\u{7EE7}\u{7EED}\u{5F55}\u{97F3}") {
                        NotificationCenter.default.post(name: .continueRecording, object: nil, userInfo: ["mode": 0])
                    }
                    .buttonStyle(.borderedProminent)
                    Button("\u{7ED3}\u{675F}\u{8BFE}\u{5802}") {
                        NotificationCenter.default.post(name: .finishLectureRecording, object: nil)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("\u{5B9E}\u{65F6}") { NotificationCenter.default.post(name: .triggerRealtime, object: nil) }
                        .buttonStyle(.borderedProminent)
                    Button("\u{5F55}\u{97F3}") { NotificationCenter.default.post(name: .triggerFile, object: nil) }
                        .buttonStyle(.bordered)
                    Button("\u{7EE7}\u{7EED}\u{5F55}\u{97F3}") {
                        NotificationCenter.default.post(name: .continueRecording, object: nil, userInfo: ["mode": 0])
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.currentSession == nil)
                }
            } else {
                Button("\u{505C}\u{6B62}") {
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

            if appState.currentSession != nil {
                Button("\u{751F}\u{6210}\u{6559}\u{6848}") {
                    NotificationCenter.default.post(name: .generateLectureNote, object: nil, userInfo: ["mode": LectureNoteMode.lessonPlan.rawValue])
                }
                .buttonStyle(.bordered)
                .disabled((appState.currentSession?.kind == .lecture
                    ? appState.currentSession?.lectureCleanText
                    : appState.currentSession?.allOriginalText)?
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

                Button("\u{751F}\u{6210}\u{590D}\u{4E60}") {
                    NotificationCenter.default.post(name: .generateLectureNote, object: nil, userInfo: ["mode": LectureNoteMode.review.rawValue])
                }
                .buttonStyle(.bordered)
                .disabled((appState.currentSession?.kind == .lecture
                    ? appState.currentSession?.lectureCleanText
                    : appState.currentSession?.allOriginalText)?
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }

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
            Button("\u{8BFE}\u{5802}\u{5BFC}\u{5165}\u{97F3}\u{9891}") {
                NotificationCenter.default.post(name: .importLectureAudio, object: nil)
            }
            .buttonStyle(.borderedProminent)

            Button("\u{8BFE}\u{5802}\u{5F55}\u{97F3}") {
                NotificationCenter.default.post(name: .startLectureRecording, object: nil)
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.state != .idle || appState.lectureRecordingActive)

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
            if appState.activeLectureSessionId != nil {
                ProgressView(value: appState.importProgress)
                    .frame(width: 140)
                Text(appState.importStageText.isEmpty ? "\u{8BFE}\u{5802}\u{8F6C}\u{5199}\u{4E2D}..." : appState.importStageText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 190, alignment: .leading)
                Button("\u{53D6}\u{6D88}") {
                    NotificationCenter.default.post(name: .cancelLectureImport, object: nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if appState.currentSession?.kind == .lecture && !appState.failedLectureSegments.isEmpty {
                let total = max(appState.lectureTotalSegments, appState.failedLectureSegments.count)
                Menu("\u{5931}\u{8D25}\u{5206}\u{6BB5} \(appState.failedLectureSegments.count)/\(total)") {
                    ForEach(appState.failedLectureSegments, id: \.self) { idx in
                        Button("\u{91CD}\u{8BD5}\u{7B2C} \(idx + 1) \u{6BB5}") {
                            NotificationCenter.default.post(name: .retryLectureSegment, object: nil, userInfo: ["index": idx])
                        }
                    }
                }
                .menuStyle(.borderlessButton)
            }
        }
    }

    private var displayText: String {
        DisplayTextResolver.resolve(
            appState: appState,
            selectedTab: appState.selectedTab,
            showGLMVersion: appState.showGLMVersion,
            lectureNoteMode: appState.lectureNoteMode
        )
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
