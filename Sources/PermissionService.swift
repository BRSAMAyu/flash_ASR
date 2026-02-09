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
    private static let systemSettingsURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")

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
        // Version-specific deep link candidates
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        var candidates: [String] = []

        if osVersion.majorVersion >= 15 {
            // macOS 15 (Sequoia)+
            candidates = [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
                "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_ListenEvent"
            ]
        } else if osVersion.majorVersion == 14 {
            // macOS 14 (Sonoma)
            candidates = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
            ]
        } else {
            // macOS 13 (Ventura)
            candidates = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
                "x-apple.systempreferences:com.apple.preference.security?Privacy"
            ]
        }

        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                Console.line("Input Monitoring deep link opened: \(raw)")
                bringSystemSettingsToFront()
                return
            }
        }

        // AppleScript fallback: navigate System Settings UI
        if openInputMonitoringViaAppleScript() {
            Console.line("Input Monitoring opened via AppleScript")
            return
        }

        // Final fallback
        NSWorkspace.shared.openApplication(at: systemSettingsURL, configuration: NSWorkspace.OpenConfiguration())
        bringSystemSettingsToFront()
        Console.line("Input Monitoring deep link failed; opened System Settings fallback.")
    }

    private static func openInputMonitoringViaAppleScript() -> Bool {
        // Try both Chinese and English UI element names
        let scriptSource = """
        tell application "System Settings"
            activate
            delay 0.5
        end tell
        tell application "System Events"
            tell process "System Settings"
                try
                    click button "隐私与安全性" of group 1 of scroll area 1 of group 1 of group 2 of splitter group 1 of group 1 of window 1
                on error
                    try
                        click button "Privacy & Security" of group 1 of scroll area 1 of group 1 of group 2 of splitter group 1 of group 1 of window 1
                    end try
                end try
                delay 0.5
                try
                    click button "输入监控" of group 1 of scroll area 1 of group 1 of group 2 of splitter group 1 of group 1 of window 1
                on error
                    try
                        click button "Input Monitoring" of group 1 of scroll area 1 of group 1 of group 2 of splitter group 1 of group 1 of window 1
                    end try
                end try
            end tell
        end tell
        """
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            return error == nil
        }
        return false
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

    static func currentAppURL() -> URL? {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL
        }
        let exec = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        var cursor = exec
        for _ in 0..<8 {
            if cursor.pathExtension == "app" {
                return cursor
            }
            cursor.deleteLastPathComponent()
        }
        return nil
    }

    static func currentAppPathString() -> String {
        currentAppURL()?.path ?? (Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? "unknown")
    }

    static func isInApplicationsFolder() -> Bool {
        guard let path = currentAppURL()?.standardizedFileURL.path else { return false }
        return path.hasPrefix("/Applications/")
    }

    static func isRunningFromTranslocationOrDMG() -> Bool {
        let path = currentAppPathString()
        return path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/")
    }

    static func revealCurrentAppInFinder() {
        if let url = currentAppURL() {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func copyCurrentAppPathToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(currentAppPathString(), forType: .string)
    }

    private static func runActivateSettings(id: String) -> Bool {
        let tool = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
        guard FileManager.default.isExecutableFile(atPath: tool) else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = ["-u", id]
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func bringSystemSettingsToFront() {
        NSWorkspace.shared.openApplication(at: systemSettingsURL, configuration: NSWorkspace.OpenConfiguration())
        let script = """
        tell application "System Settings" to activate
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            _ = appleScript.executeAndReturnError(&error)
        }
    }
}
