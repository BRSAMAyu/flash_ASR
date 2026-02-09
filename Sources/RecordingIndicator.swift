import SwiftUI
import AppKit
import Combine

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

    private let compactSize = NSSize(width: 300, height: 56)
    private let expandedSize = NSSize(width: 420, height: 380)

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
            onSwitchLevel: { [weak self] level in self?.onSwitchLevel?(level) }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: compactSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: compactSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
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
    var settings: SettingsManager
    var onStopTapped: () -> Void
    var onCopyTapped: () -> Void
    var onCloseTapped: () -> Void
    var onCancelMarkdown: () -> Void
    var onContinueRecording: (CaptureMode) -> Void
    var onSaveToObsidian: () -> Void
    var onFullRefinement: (MarkdownLevel) -> Void
    var onSwitchLevel: (MarkdownLevel) -> Void
    @State private var pulse = false
    @State private var showToast = false
    @State private var toastText = ""

    private var isInExpandedMode: Bool {
        let hasSession = appState.currentSession != nil
        let hasMarkdown = appState.markdownProcessing || !appState.markdownText.isEmpty || !appState.originalText.isEmpty
        let isListening = appState.state == .listening
        return (hasSession || hasMarkdown) && !isListening
    }

    var body: some View {
        if isInExpandedMode {
            expandedBody
        } else {
            compactBody
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
            // Header: tab picker + status
            HStack(spacing: 6) {
                ForEach(MarkdownTab.allCases, id: \.rawValue) { tab in
                    Button(action: {
                        if let level = tab.markdownLevel {
                            onSwitchLevel(level)
                        } else {
                            // Original tab
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

                Spacer()

                if appState.markdownProcessing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                        if let level = appState.generatingLevel {
                            Text("\(level.displayName)\u{6574}\u{7406}\u{4E2D}...")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.8))
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
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()
                .background(Color.white.opacity(0.2))

            // Content area
            ScrollView {
                Text(displayText)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .frame(maxHeight: .infinity)

            // Round info
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

            // Bottom buttons
            HStack(spacing: 8) {
                Button(action: {
                    let text = displayText
                    guard !text.isEmpty else { return }
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                    triggerToast("\u{5DF2}\u{590D}\u{5236}")
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.clipboard")
                        Text("\u{590D}\u{5236}")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)

                if !settings.obsidianVaultPath.isEmpty {
                    Button(action: onSaveToObsidian) {
                        HStack(spacing: 3) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Obsidian")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                }

                if let session = appState.currentSession, session.rounds.count > 1 {
                    Button(action: {
                        let level = MarkdownLevel(rawValue: settings.defaultMarkdownLevel) ?? .light
                        onFullRefinement(level)
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("\u{5168}\u{6587}\u{91CD}\u{6392}")
                        }
                        .font(.system(size: 11))
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
                    Button(action: {
                        onContinueRecording(.realtime)
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "mic.fill")
                            Text("\u{7EE7}\u{7EED}\u{5F55}\u{97F3}")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                }

                Button(action: onCloseTapped) {
                    Text("\u{5173}\u{95ED}")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
            }
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
        .frame(width: 420, height: 380)
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

    private var displayText: String {
        if appState.selectedTab == .original {
            if let session = appState.currentSession {
                return session.allOriginalText
            }
            return appState.originalText
        }

        // Markdown tabs - show streaming text if processing, else session data
        if appState.markdownProcessing && !appState.markdownText.isEmpty {
            return appState.markdownText
        }

        if let session = appState.currentSession,
           let level = appState.selectedTab.markdownLevel {
            let combined = session.combinedMarkdown(level: level)
            if !combined.isEmpty { return combined }
        }

        return appState.markdownText
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
        if appState.mode == .fileFlash, appState.state == .listening, let remain = appState.remainingRecordSeconds {
            return "\u{5F55}\u{97F3}\u{6A21}\u{5F0F} | \u{5269}\u{4F59} \(remain) \u{79D2}"
        }
        if !appState.currentTranscript.isEmpty {
            return String(appState.currentTranscript.suffix(35))
        }
        return appState.mode == .fileFlash ? "\u{5F55}\u{97F3}\u{6A21}\u{5F0F}" : "\u{5B9E}\u{65F6}\u{6A21}\u{5F0F}"
    }
}
