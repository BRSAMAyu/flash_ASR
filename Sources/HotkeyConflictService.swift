import Foundation
import Carbon
import AppKit

enum HotkeyConflictService {
    static func hasConflict(keyCode: Int, modifiers: Int) -> Bool {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x46414B45), id: UInt32(Int.random(in: 1000...65000))) // 'FAKE'
        let status = RegisterEventHotKey(UInt32(keyCode), carbonModifiers(from: modifiers), hkID, GetEventDispatcherTarget(), 0, &ref)
        if status == noErr {
            if let ref { UnregisterEventHotKey(ref) }
            return false
        }
        return true
    }

    private static func carbonModifiers(from nsModsRaw: Int) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(nsModsRaw))
        var out: UInt32 = 0
        if flags.contains(.command) { out |= UInt32(cmdKey) }
        if flags.contains(.option) { out |= UInt32(optionKey) }
        if flags.contains(.control) { out |= UInt32(controlKey) }
        if flags.contains(.shift) { out |= UInt32(shiftKey) }
        return out
    }
}
