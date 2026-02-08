import SwiftUI
import AppKit
import Carbon

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    let displayString: String
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.displayString = displayString
        view.onHotkeyRecorded = { code, mods in
            keyCode = code
            modifiers = mods
            onStopRecording?()
        }
        view.onRecordingStarted = {
            onStartRecording?()
        }
        view.onRecordingCancelled = {
            onStopRecording?()
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.displayString = displayString
        nsView.needsDisplay = true
    }
}

class HotkeyRecorderNSView: NSView {
    var onHotkeyRecorded: ((Int, Int) -> Void)?
    var onRecordingStarted: (() -> Void)?
    var onRecordingCancelled: (() -> Void)?
    var displayString = ""
    private var isRecording = false
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupTracking()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTracking()
    }

    private func setupTracking() {
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            isRecording = false
            onRecordingCancelled?()
            needsDisplay = true
            return
        }
        isRecording = true
        onRecordingStarted?()
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        let code = Int(event.keyCode)
        let mods = Int(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)

        // Escape cancels recording
        if code == kVK_Escape {
            isRecording = false
            onRecordingCancelled?()
            needsDisplay = true
            return
        }

        // Require at least one modifier
        guard mods != 0 else { return }

        isRecording = false
        onHotkeyRecorded?(code, mods)
        needsDisplay = true
    }

    override func flagsChanged(with event: NSEvent) {
        // Allow modifier-only awareness but don't record modifier-only combos
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 160, height: 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)

        // Background
        let bgColor: NSColor
        if isRecording {
            bgColor = NSColor.controlAccentColor.withAlphaComponent(0.15)
        } else if isHovered {
            bgColor = NSColor.controlBackgroundColor.blended(withFraction: 0.05, of: .controlAccentColor) ?? .controlBackgroundColor
        } else {
            bgColor = NSColor.controlBackgroundColor
        }

        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        bgColor.setFill()
        path.fill()

        // Border
        let borderColor: NSColor = isRecording ? .controlAccentColor : .separatorColor
        borderColor.setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        // Text
        let text: String
        if isRecording {
            text = "Press shortcut..."
        } else {
            text = displayString.isEmpty ? "Click to set" : displayString
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: isRecording ? .medium : .regular),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrStr.size()
        let textRect = NSRect(
            x: (rect.width - textSize.width) / 2 + rect.origin.x,
            y: (rect.height - textSize.height) / 2 + rect.origin.y,
            width: textSize.width,
            height: textSize.height
        )
        attrStr.draw(in: textRect)
    }
}
