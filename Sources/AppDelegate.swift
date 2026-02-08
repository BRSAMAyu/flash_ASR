import AppKit
import SwiftUI
import ServiceManagement

final class FlashASRDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let settings = SettingsManager.shared
    let appState = AppStatePublisher()
    var appController: AppController!
    private var recordingIndicator: RecordingIndicatorController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appController = AppController(settings: settings, statePublisher: appState)

        recordingIndicator = RecordingIndicatorController(settings: settings)
        appController.recordingIndicator = recordingIndicator

        appController.start()

        if !settings.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showOnboarding()
            }
        }
    }

    private func showOnboarding() {
        let onboardingView = OnboardingView()
            .environmentObject(settings)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "\u{6B22}\u{8FCE}\u{4F7F}\u{7528} FlashASR"
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.isReleasedWhenClosed = false

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.checkAndHideDock()
            }
        }
    }

    func checkAndHideDock() {
        let visibleWindows = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) && $0.level == .normal }
        if visibleWindows.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
