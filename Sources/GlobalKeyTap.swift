import Foundation
import Carbon

enum AppState {
    case idle
    case listening
    case stopping
}

enum CaptureMode {
    case realtime
    case fileFlash
}

enum TriggerAction {
    case realtimeToggle
    case fileToggle
}

final class GlobalKeyTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let onTrigger: (TriggerAction) -> Void
    private let settings: SettingsManager
    private var paused = false

    init(settings: SettingsManager, onTrigger: @escaping (TriggerAction) -> Void) {
        self.settings = settings
        self.onTrigger = onTrigger
    }

    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let callback: CGEventTapCallBack = { _, type, event, userData in
            guard let userData else {
                return Unmanaged.passUnretained(event)
            }
            let me = Unmanaged<GlobalKeyTap>.fromOpaque(userData).takeUnretainedValue()
            guard !me.paused else { return Unmanaged.passUnretained(event) }

            if type == .keyDown {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let relevantMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
                let normalizedFlags = flags.intersection(relevantMask)

                let s = me.settings

                // Check realtime hotkey
                let rtKey = Int64(s.realtimeHotkeyCode)
                let rtMods = CGEventFlags(rawValue: UInt64(s.realtimeHotkeyModifiers)).intersection(relevantMask)
                if keyCode == rtKey && normalizedFlags == rtMods {
                    me.onTrigger(.realtimeToggle)
                    return nil
                }

                // Check file hotkey
                let fileKey = Int64(s.fileHotkeyCode)
                let fileMods = CGEventFlags(rawValue: UInt64(s.fileHotkeyModifiers)).intersection(relevantMask)
                if keyCode == fileKey && normalizedFlags == fileMods {
                    me.onTrigger(.fileToggle)
                    return nil
                }

                return Unmanaged.passUnretained(event)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: userData
        ) else {
            return false
        }

        tap = eventTap
        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            tap = nil
            return false
        }
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    func pause() {
        paused = true
    }

    func resume() {
        paused = false
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            self.source = nil
        }
        if let tap {
            CFMachPortInvalidate(tap)
            self.tap = nil
        }
    }
}
