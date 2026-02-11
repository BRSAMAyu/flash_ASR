import AppKit
import SwiftUI

final class DashboardWindowController {
    private weak var window: NSWindow?

    func show(appState: AppStatePublisher, settings: SettingsManager) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            appState.dashboardVisible = true
            return
        }

        let root = DashboardView()
            .environmentObject(appState)
            .environmentObject(settings)
        let host = NSHostingView(rootView: root)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "FlashASR"
        win.contentView = host
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window = win
        appState.dashboardVisible = true

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            self?.window = nil
            appState.dashboardVisible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let visibleWindows = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) && $0.level == .normal }
                if visibleWindows.isEmpty {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
}
