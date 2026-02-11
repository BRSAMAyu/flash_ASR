import SwiftUI
import AppKit
import Combine

final class RecordingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

class RecordingIndicatorController {
    private var panel: NSPanel?
    private let settings: SettingsManager
    private var cancellables = Set<AnyCancellable>()
    var onStopTapped: (() -> Void)?
    var onCopyTapped: (() -> Void)?
    var onCloseTapped: (() -> Void)?
    var onCancelMarkdown: (() -> Void)?
    var onContinueRecording: ((CaptureMode) -> Void)?
    var onSaveToObsidian: (() -> Void)?
    var onFullRefinement: ((MarkdownLevel) -> Void)?
    var onSwitchLevel: ((MarkdownLevel) -> Void)?
    var onToggleGLM: (() -> Void)?

    private let compactSize = NSSize(width: 300, height: 56)
    private let expandedSize = NSSize(width: 500, height: 430)

    init(settings: SettingsManager) {
        self.settings = settings
    }

    func show(state: AppStatePublisher) {
        guard settings.showRecordingIndicator else { return }
        guard panel == nil else { return }

        let view = RecordingIndicatorView(
            appState: state,
            settings: settings,
            onStopTapped: { [weak self] in self?.onStopTapped?() },
            onCopyTapped: { [weak self] in self?.onCopyTapped?() },
            onCloseTapped: { [weak self] in self?.onCloseTapped?() },
            onCancelMarkdown: { [weak self] in self?.onCancelMarkdown?() },
            onContinueRecording: { [weak self] mode in self?.onContinueRecording?(mode) },
            onSaveToObsidian: { [weak self] in self?.onSaveToObsidian?() },
            onFullRefinement: { [weak self] level in self?.onFullRefinement?(level) },
            onSwitchLevel: { [weak self] level in self?.onSwitchLevel?(level) },
            onToggleGLM: { [weak self] in self?.onToggleGLM?() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: compactSize)

        let panel = RecordingOverlayPanel(
            contentRect: NSRect(origin: .zero, size: compactSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let x = (screen.frame.width - compactSize.width) / 2
            let y = screen.visibleFrame.maxY - 60
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        self.panel = panel

        // Watch for markdown mode / session to resize panel
        cancellables.removeAll()
        state.$markdownProcessing
            .combineLatest(state.$markdownText, state.$currentSession)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] processing, mdText, session in
                guard let self, let panel = self.panel else { return }
                let hasContent = processing || !mdText.isEmpty || session != nil
                let currentWidth = panel.frame.width
                let isListening = state.state == .listening
                if hasContent && !isListening && currentWidth < self.expandedSize.width {
                    self.expandPanel()
                }
            }
            .store(in: &cancellables)
    }

    private func expandPanel() {
        guard let panel else { return }
        let oldFrame = panel.frame
        let newY = oldFrame.maxY - expandedSize.height
        let newX = oldFrame.origin.x - (expandedSize.width - oldFrame.width) / 2
        let newFrame = NSRect(origin: NSPoint(x: newX, y: newY), size: expandedSize)
        panel.animator().setFrame(newFrame, display: true)
    }

    func hide() {
        cancellables.removeAll()
        panel?.orderOut(nil)
        panel = nil
    }
}

struct RecordingIndicatorView: View {
    @ObservedObject var appState: AppStatePublisher
    @ObservedObject var settings: SettingsManager
    var onStopTapped: () -> Void
    var onCopyTapped: () -> Void
    var onCloseTapped: () -> Void
    var onCancelMarkdown: () -> Void
    var onContinueRecording: (CaptureMode) -> Void
    var onSaveToObsidian: () -> Void
    var onFullRefinement: (MarkdownLevel) -> Void
    var onSwitchLevel: (MarkdownLevel) -> Void
    var onToggleGLM: () -> Void
    @State private var pulse = false
    @State private var showToast = false
    @State private var toastText = ""
    
    private var isLectureSession: Bool {
        appState.currentSession?.kind == .lecture
    }

    private var lectureSourceText: String {
        guard let session = appState.currentSession else { return "" }
        return (session.kind == .lecture ? session.lectureCleanText : session.allOriginalText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canGenerateLectureNotes: Bool {
        !lectureSourceText.isEmpty
    }

    private var canTogglePreview: Bool {
        if isLectureSession {
            return appState.lectureNoteMode != .transcript
        }
        return appState.selectedTab != .original
    }

    private var shouldUsePreviewPanel: Bool {
        settings.panelPreviewEnabled && canTogglePreview
    }

    private var isInExpandedMode: Bool {
        let hasSession = appState.currentSession != nil
        let hasMarkdown = appState.markdownProcessing || !appState.markdownText.isEmpty || !appState.originalText.isEmpty
        let isListening = appState.state == .listening
        return (hasSession || hasMarkdown) && !isListening
    }

    var body: some View {
        Group {
            if isInExpandedMode {
                expandedBody
            } else {
                compactBody
            }
        }
        .onAppear {
            syncEditableTextFromDisplay()
        }
        .onChange(of: appState.selectedTab) { _, _ in
            appState.lectureNoteMode = .transcript
            syncEditableTextFromDisplay()
        }
        .onChange(of: appState.currentSession?.id) { _, _ in
            syncEditableTextFromDisplay()
        }
        .onChange(of: appState.lectureNoteMode) { _, _ in
            syncEditableTextFromDisplay()
        }
    }

    // MARK: - Compact mode (recording)

    var compactBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(appState.state == .stopping ? Color.orange : Color.red)
                    .frame(width: 10, height: 10)
                    .scaleEffect(pulse ? 1.3 : 1.0)
                    .opacity(pulse ? 0.7 : 1.0)
                    .animation(
                        appState.state == .listening
                            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .default,
                        value: pulse
                    )
                    .onAppear { pulse = true }

                VStack(alignment: .leading, spacing: 2) {
                    Text(modeText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)

                    Text(subtitleText)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if appState.state == .listening {
                    Button(action: onStopTapped) {
                        Image(systemName: "stop.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("\u{505C}\u{6B62}\u{5E76}\u{5B8C}\u{6210}")
                }

                Button(action: onCopyTapped) {
                    Image(systemName: "doc.on.doc.fill")
                        .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("\u{590D}\u{5236}\u{4E0A}\u{6B21}\u{7ED3}\u{679C}")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Audio level bar
            if appState.state == .listening {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.green)
                        .frame(width: geo.size.width * CGFloat(appState.audioLevel), height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, 4)
                .padding(.bottom, 2)
            }
        }
        .frame(width: 300, height: 56)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.7))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Expanded mode (session view)

    var expandedBody: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Header: primary switch row + secondary status row
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        if isLectureSession {
                            Picker("", selection: $appState.lectureNoteMode) {
                                Text(LectureNoteMode.transcript.displayName).tag(LectureNoteMode.transcript)
                                Text(LectureNoteMode.lessonPlan.displayName).tag(LectureNoteMode.lessonPlan)
                                Text(LectureNoteMode.review.displayName).tag(LectureNoteMode.review)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 270)
                        } else {
                            ForEach(MarkdownTab.allCases, id: \.rawValue) { tab in
                                Button(action: {
                                    if let level = tab.markdownLevel {
                                        onSwitchLevel(level)
                                    } else {
                                        appState.selectedTab = .original
                                    }
                                }) {
                                    Text(tab.displayName)
                                        .font(.system(size: 11, weight: appState.selectedTab == tab ? .bold : .regular))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            appState.selectedTab == tab
                                                ? Color.white.opacity(0.2)
                                                : Color.clear
                                        )
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.white)
                            }

                            if settings.llmMode != "mimo" && appState.selectedTab != .original {
                                Button(action: onToggleGLM) {
                                    HStack(spacing: 4) {
                                        Text("GLM")
                                            .font(.system(size: 11, weight: appState.showGLMVersion ? .bold : .regular))
                                        if appState.glmProcessing {
                                            ProgressView()
                                                .scaleEffect(0.5)
                                                .frame(width: 10, height: 10)
                                        }
                                    }
                                    .frame(minWidth: 48)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        appState.showGLMVersion
                                            ? Color.purple.opacity(0.5)
                                            : (glmHasContent ? Color.purple.opacity(0.2) : Color.clear)
                                    )
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(
                                    appState.glmProcessing ? .purple :
                                        (glmHasContent ? .purple : .white.opacity(0.5))
                                )
                                .fixedSize(horizontal: true, vertical: false)
                                .layoutPriority(3)
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        if !isLectureSession, appState.currentSession != nil {
                            Picker("", selection: $appState.lectureNoteMode) {
                                Text("\u{5E38}\u{89C4}").tag(LectureNoteMode.transcript)
                                Text("\u{6559}\u{6848}").tag(LectureNoteMode.lessonPlan)
                                Text("\u{590D}\u{4E60}").tag(LectureNoteMode.review)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                        }

                        if appState.markdownProcessing || appState.glmProcessing {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 12, height: 12)
                                if let level = appState.generatingLevel {
                                    Text("\(level.displayName)\u{6574}\u{7406}\u{4E2D}...")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.8))
                                } else if appState.glmProcessing, let level = appState.glmGeneratingLevel {
                                    Text("GLM \(level.displayName)...")
                                        .font(.system(size: 10))
                                        .foregroundColor(.purple.opacity(0.8))
                                } else {
                                    Text("\u{6574}\u{7406}\u{4E2D}...")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                        } else if let err = appState.markdownError {
                            Text(err)
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        Toggle("\u{7F16}\u{8F91}", isOn: $appState.panelEditingEnabled)
                            .font(.system(size: 11))
                            .toggleStyle(.switch)
                            .scaleEffect(0.85)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider()
                    .background(Color.white.opacity(0.2))

                if appState.activeLectureSessionId != nil || (isLectureSession && !appState.failedLectureSegments.isEmpty) {
                    HStack(spacing: 8) {
                        if appState.activeLectureSessionId != nil {
                            ProgressView(value: appState.importProgress)
                                .frame(width: 95)
                            Text(appState.importStageText.isEmpty ? "\u{8BFE}\u{5802}\u{8F6C}\u{5199}\u{4E2D}..." : appState.importStageText)
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(1)
                                .frame(maxWidth: 180, alignment: .leading)
                            Button("\u{53D6}\u{6D88}") {
                                NotificationCenter.default.post(name: .cancelLectureImport, object: nil)
                            }
                            .buttonStyle(.bordered)
                        }
                        if isLectureSession && !appState.failedLectureSegments.isEmpty {
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
                        Spacer()
                    }
                    .controlSize(.small)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)

                    Divider()
                        .background(Color.white.opacity(0.2))
                }

                // Content area
                if appState.panelEditingEnabled {
                    VStack(spacing: 6) {
                        TextEditor(text: $appState.editableText)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(8)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(8)
                        HStack(spacing: 8) {
                            Button("\u{8F6C}\u{5199}") {
                                let level = appState.selectedTab.markdownLevel ?? (MarkdownLevel(rawValue: settings.defaultMarkdownLevel) ?? .light)
                                NotificationCenter.default.post(name: .processManualText, object: nil, userInfo: ["text": appState.editableText, "level": level.rawValue])
                            }
                            .buttonStyle(.bordered)
                            .disabled(appState.editableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button("\u{64A4}\u{56DE}") {
                                NotificationCenter.default.post(name: .undoTransform, object: nil)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!appState.canUndoTransform)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                    }
                    .padding(6)
                } else if shouldUsePreviewPanel {
                    MarkdownPreviewView(markdown: displayText)
                        .environment(\.colorScheme, .dark)
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(displayText)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(12)
                    }
                    .frame(maxHeight: .infinity)
                }

                if let session = appState.currentSession, session.rounds.count > 1 {
                    HStack {
                        Text("\(session.rounds.count) \u{8F6E}\u{8F6C}\u{5199}")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 2)
                }

                Divider()
                    .background(Color.white.opacity(0.2))

                HStack(spacing: 6) {
                    Button(action: {
                        let text = displayText
                        guard !text.isEmpty else { return }
                        let isMarkdown = isLectureSession
                            ? appState.lectureNoteMode != .transcript
                            : appState.selectedTab != .original
                        if isMarkdown {
                            RichClipboard.shared.writeMultiFormat(markdown: text)
                        } else {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(text, forType: .string)
                        }
                        triggerToast("\u{5DF2}\u{590D}\u{5236}")
                    }) {
                        Label("\u{590D}\u{5236}", systemImage: "doc.on.clipboard")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)

                    if canTogglePreview {
                        Button(settings.panelPreviewEnabled ? "\u{6E90}\u{7801}" : "\u{9884}\u{89C8}") {
                            settings.panelPreviewEnabled.toggle()
                        }
                        .buttonStyle(.bordered)
                    }

                    if !settings.obsidianVaultPath.isEmpty {
                        Button(action: onSaveToObsidian) {
                            Label("\u{5BFC}\u{51FA}", systemImage: "square.and.arrow.down")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                    }

                    if !isLectureSession, let session = appState.currentSession, session.rounds.count > 1 {
                        Button(action: {
                            let level = MarkdownLevel(rawValue: settings.defaultMarkdownLevel) ?? .light
                            onFullRefinement(level)
                        }) {
                            Label("\u{5168}\u{6587}", systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                    }

                    if appState.currentSession != nil && canGenerateLectureNotes {
                        Button("\u{6559}\u{6848}") {
                            NotificationCenter.default.post(
                                name: .generateLectureNote,
                                object: nil,
                                userInfo: ["mode": LectureNoteMode.lessonPlan.rawValue]
                            )
                        }
                        .buttonStyle(.bordered)
                        Button("\u{590D}\u{4E60}") {
                            NotificationCenter.default.post(
                                name: .generateLectureNote,
                                object: nil,
                                userInfo: ["mode": LectureNoteMode.review.rawValue]
                            )
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    if appState.markdownProcessing {
                        Button(action: onCancelMarkdown) {
                            Text("\u{53D6}\u{6D88}")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                    }

                    if appState.state == .idle {
                        Menu {
                            Button("\u{5B9E}\u{65F6}\u{8F6C}\u{5199}") {
                                NotificationCenter.default.post(name: .triggerRealtime, object: nil)
                            }
                            Button("\u{5F55}\u{97F3}\u{8F6C}\u{5199}") {
                                NotificationCenter.default.post(name: .triggerFile, object: nil)
                            }
                            if appState.currentSession != nil {
                                Divider()
                                Button("\u{7EE7}\u{7EED}\u{5B9E}\u{65F6}") {
                                    onContinueRecording(.realtime)
                                }
                                Button("\u{7EE7}\u{7EED}\u{5F55}\u{97F3}") {
                                    onContinueRecording(.fileFlash)
                                }
                            }
                            Divider()
                            Button("\u{8BFE}\u{5802}\u{5F55}\u{97F3}") {
                                NotificationCenter.default.post(name: .startLectureRecording, object: nil)
                            }
                            .disabled(appState.lectureRecordingActive)
                            Button("\u{8BFE}\u{5802}\u{5BFC}\u{5165}\u{97F3}\u{9891}") {
                                NotificationCenter.default.post(name: .importLectureAudio, object: nil)
                            }
                        } label: {
                            Label("\u{5F00}\u{59CB}", systemImage: "mic.badge.plus")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                    }

                    if appState.lectureRecordingActive {
                        Button("\u{7ED3}\u{675F}\u{8BFE}\u{5802}") {
                            NotificationCenter.default.post(name: .finishLectureRecording, object: nil)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(action: onCloseTapped) {
                        Text("\u{5173}\u{95ED}")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.small)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            // Toast overlay
            if showToast {
                Text(toastText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .padding(.top, 50)
            }
        }
        .frame(width: 500, height: 430)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.7))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: appState.toastMessage) { _, msg in
            if let msg, !msg.isEmpty {
                triggerToast(msg)
                appState.toastMessage = nil
            }
        }
    }

    private func triggerToast(_ message: String) {
        toastText = message
        withAnimation(.easeInOut(duration: 0.2)) {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showToast = false
            }
        }
    }

    private func syncEditableTextFromDisplay() {
        let text = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        appState.editableText = text
    }

    private var glmHasContent: Bool {
        guard let session = appState.currentSession,
              let level = appState.selectedTab.markdownLevel else { return false }
        return !session.combinedGLMMarkdown(level: level).isEmpty
    }

    private var displayText: String {
        DisplayTextResolver.resolve(
            appState: appState,
            selectedTab: appState.selectedTab,
            showGLMVersion: appState.showGLMVersion,
            lectureNoteMode: appState.lectureNoteMode
        )
    }

    var modeText: String {
        switch appState.state {
        case .listening:
            return appState.mode == .realtime ? "\u{5B9E}\u{65F6}\u{8F6C}\u{5199}" : "\u{6B63}\u{5728}\u{5F55}\u{97F3}..."
        case .stopping:
            return "\u{8F6C}\u{5199}\u{4E2D}..."
        case .idle:
            return "\u{5C31}\u{7EEA}"
        }
    }

    var subtitleText: String {
        if appState.state == .listening, let elapsed = appState.elapsedRecordSeconds {
            if let limit = appState.recordLimitSeconds {
                return "\u{5F55}\u{97F3}\u{6A21}\u{5F0F} | \u{5DF2}\u{5F55} \(formatDuration(elapsed)) / \u{4E0A}\u{9650} \(formatDuration(limit))"
            }
            return "\u{5F55}\u{97F3}\u{6A21}\u{5F0F} | \u{5DF2}\u{5F55} \(formatDuration(elapsed))"
        }
        if !appState.currentTranscript.isEmpty {
            return String(appState.currentTranscript.suffix(35))
        }
        return appState.mode == .fileFlash ? "\u{5F55}\u{97F3}\u{6A21}\u{5F0F}" : "\u{5B9E}\u{65F6}\u{6A21}\u{5F0F}"
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
