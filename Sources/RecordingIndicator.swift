import SwiftUI
import AppKit

class RecordingIndicatorController {
    private var panel: NSPanel?
    private let settings: SettingsManager

    init(settings: SettingsManager) {
        self.settings = settings
    }

    func show(state: AppStatePublisher) {
        guard settings.showRecordingIndicator else { return }
        guard panel == nil else { return }

        let view = RecordingIndicatorView(appState: state)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 220, height: 48)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 48),
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

        // Position near top center of screen
        if let screen = NSScreen.main {
            let x = (screen.frame.width - 220) / 2
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
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            // Animated dot
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

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 220, height: 48)
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
            return appState.mode == .realtime ? "Realtime ASR" : "Recording..."
        case .stopping:
            return "Processing..."
        case .idle:
            return "Ready"
        }
    }
}
