import Foundation
import AVFoundation
import ApplicationServices
import AppKit

struct PermissionSnapshot {
    var microphone: Bool
    var accessibility: Bool
    var inputMonitoring: Bool

    var allGranted: Bool {
        microphone && accessibility && inputMonitoring
    }
}

enum PermissionService {
    static func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: microphoneGranted(),
            accessibility: accessibilityGranted(prompt: false),
            inputMonitoring: inputMonitoringGranted()
        )
    }

    static func microphoneGranted() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestMicrophone(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    static func accessibilityGranted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestAccessibilityPrompt() {
        _ = accessibilityGranted(prompt: true)
    }

    static func inputMonitoringGranted() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightListenEventAccess()
        }
        return true
    }

    static func requestInputMonitoringPrompt() {
        if #available(macOS 10.15, *) {
            _ = CGRequestListenEventAccess()
        }
    }

    static func openInputMonitoringSettings() {
        // Different macOS versions accept different anchors for Input Monitoring.
        let candidates = [
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_Keyboard",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Keyboard",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ]
        for item in candidates {
            if let url = URL(string: item), NSWorkspace.shared.open(url) {
                return
            }
        }
        if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            _ = NSWorkspace.shared.open(fallback)
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            _ = NSWorkspace.shared.open(url)
        }
    }

    static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            _ = NSWorkspace.shared.open(url)
        }
    }
}
