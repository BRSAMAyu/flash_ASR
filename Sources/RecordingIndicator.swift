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

    private let compactSize = NSSize(width: 300, height: 56)
    private let expandedSize = NSSize(width: 380, height: 320)

    init(settings: SettingsManager) {
        self.settings = settings
    }

    func show(state: AppStatePublisher) {
        guard settings.showRecordingIndicator else { return }
        guard panel == nil else { return }

        let view = RecordingIndicatorView(
            appState: state,
            onStopTapped: { [weak self] in self?.onStopTapped?() },
            onCopyTapped: { [weak self] in self?.onCopyTapped?() },
            onCloseTapped: { [weak self] in self?.onCloseTapped?() },
            onCancelMarkdown: { [weak self] in self?.onCancelMarkdown?() }
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

        // Watch for markdown mode to resize panel
        cancellables.removeAll()
        state.$markdownProcessing
            .combineLatest(state.$markdownText, state.$originalText)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] processing, mdText, origText in
                guard let self, let panel = self.panel else { return }
                let hasMarkdownContent = processing || !mdText.isEmpty || !origText.isEmpty
                let currentWidth = panel.frame.width
                if hasMarkdownContent && currentWidth < self.expandedSize.width {
                    self.expandPanel()
                }
            }
            .store(in: &cancellables)
    }

    private func expandPanel() {
        guard let panel else { return }
        let oldFrame = panel.frame
        // Expand downward from current top position
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
    var onStopTapped: () -> Void
    var onCopyTapped: () -> Void
    var onCloseTapped: () -> Void
    var onCancelMarkdown: () -> Void
    @State private var pulse = false
    @State private var showingMarkdown = true

    private var isInMarkdownResultMode: Bool {
        appState.markdownProcessing || !appState.markdownText.isEmpty || !appState.originalText.isEmpty
    }

    var body: some View {
        if isInMarkdownResultMode {
            expandedBody
        } else {
            compactBody
        }
    }

    // MARK: - Compact mode (recording)

    var compactBody: some View {
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

    // MARK: - Expanded mode (Markdown result)

    var expandedBody: some View {
        VStack(spacing: 0) {
            // Header: tab picker + status
            HStack {
                Picker("", selection: $showingMarkdown) {
                    Text("\u{539F}\u{6587}").tag(false)
                    Text("Markdown").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Spacer()

                if appState.markdownProcessing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                        Text("\u{6574}\u{7406}\u{4E2D}...")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.8))
                    }
                } else if let err = appState.markdownError {
                    Text(err)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .lineLimit(1)
                } else if !appState.markdownText.isEmpty {
                    Text("\u{2705} \u{5DF2}\u{5B8C}\u{6210}")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()
                .background(Color.white.opacity(0.2))

            // Content area
            ScrollView {
                Text(showingMarkdown ? appState.markdownText : appState.originalText)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .frame(maxHeight: .infinity)

            Divider()
                .background(Color.white.opacity(0.2))

            // Bottom buttons
            HStack {
                Button(action: {
                    let text = showingMarkdown ? appState.markdownText : appState.originalText
                    guard !text.isEmpty else { return }
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.clipboard")
                        Text("\u{590D}\u{5236}")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)

                Spacer()

                if appState.markdownProcessing {
                    Button(action: onCancelMarkdown) {
                        Text("\u{53D6}\u{6D88}")
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
        .frame(width: 380, height: 320)
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
