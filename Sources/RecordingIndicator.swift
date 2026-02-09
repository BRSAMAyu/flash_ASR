import SwiftUI
import AppKit

class RecordingIndicatorController {
    private var panel: NSPanel?
    private let settings: SettingsManager
    var onStopTapped: (() -> Void)?
    var onCopyTapped: (() -> Void)?

    init(settings: SettingsManager) {
        self.settings = settings
    }

    func show(state: AppStatePublisher) {
        guard settings.showRecordingIndicator else { return }
        guard panel == nil else { return }

        let view = RecordingIndicatorView(
            appState: state,
            onStopTapped: { [weak self] in self?.onStopTapped?() },
            onCopyTapped: { [weak self] in self?.onCopyTapped?() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 56)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 56),
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
            let x = (screen.frame.width - 300) / 2
            let y = screen.visibleFrame.maxY - 60
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct RecordingIndicatorView: View {
    @ObservedObject var appState: AppStatePublisher
    var onStopTapped: () -> Void
    var onCopyTapped: () -> Void
    @State private var pulse = false

    var body: some View {
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

                if !appState.currentTranscript.isEmpty {
                    Text(String(appState.currentTranscript.suffix(35)))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if appState.state == .listening {
                Button(action: onStopTapped) {
                    Image(systemName: "stop.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Stop and finalize")
            }

            Button(action: onCopyTapped) {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help("Copy last final text")
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
}
