import AppKit
import SwiftUI
import ServiceManagement

final class FlashASRDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let settings = SettingsManager.shared
    let appState = AppStatePublisher()
    var appController: AppController!
    private var recordingIndicator: RecordingIndicatorController?
    private var permissionWindow: NSWindow?
    private var permissionGuideDismissed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        appController = AppController(settings: settings, statePublisher: appState)
        appController.onPermissionChanged = { [weak self] snapshot in
            self?.handlePermissionUpdate(snapshot)
        }

        recordingIndicator = RecordingIndicatorController(settings: settings)
        recordingIndicator?.onStopTapped = { [weak self] in
            self?.appController.stopFromIndicator()
        }
        recordingIndicator?.onCopyTapped = { [weak self] in
            self?.appController.copyLastFinalToClipboard()
        }
        recordingIndicator?.onCloseTapped = { [weak self] in
            self?.appController.closeSession()
        }
        recordingIndicator?.onCancelMarkdown = { [weak self] in
            self?.appController.cancelMarkdown()
        }
        // v4 callbacks
        recordingIndicator?.onContinueRecording = { [weak self] mode in
            self?.appController.continueRecording(mode: mode)
        }
        recordingIndicator?.onSaveToObsidian = { [weak self] in
            self?.appController.saveToObsidian()
        }
        recordingIndicator?.onFullRefinement = { [weak self] level in
            self?.appController.triggerFullRefinement(level: level)
        }
        recordingIndicator?.onSwitchLevel = { [weak self] level in
            self?.appController.switchMarkdownLevel(level)
        }
        recordingIndicator?.onToggleGLM = { [weak self] in
            self?.appController.toggleGLMVersion()
        }
        appController.recordingIndicator = recordingIndicator

        appController.start()
        NotificationCenter.default.addObserver(forName: .openPermissionsGuide, object: nil, queue: .main) { [weak self] _ in
            self?.permissionGuideDismissed = false
            self?.showPermissionGuide()
        }
        NotificationCenter.default.addObserver(forName: .openOnboarding, object: nil, queue: .main) { [weak self] _ in
            self?.showOnboarding()
        }
        NotificationCenter.default.addObserver(forName: .copyPermissionSelfCheck, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            DiagnosticsService.copyPermissionSelfCheck(state: self.appState)
        }
        NotificationCenter.default.addObserver(forName: .exportDiagnostics, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            do {
                let out = try DiagnosticsService.export(settings: self.settings, state: self.appState)
                NSWorkspace.shared.activateFileViewerSelecting([out])
            } catch {
                self.appState.errorMessage = "Export diagnostics failed: \\(error.localizedDescription)"
            }
        }

        if !settings.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showOnboarding()
            }
        }
    }

    private func handlePermissionUpdate(_ snapshot: PermissionSnapshot) {
        if snapshot.allGranted {
            permissionWindow?.close()
            permissionWindow = nil
            permissionGuideDismissed = false
            return
        }
        // Don't auto-show permission guide during onboarding (it has its own permission step)
        guard settings.hasCompletedOnboarding else { return }
        if permissionWindow == nil && !permissionGuideDismissed {
            showPermissionGuide()
        }
    }

    private func showPermissionGuide() {
        if let permissionWindow {
            permissionWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = PermissionGateView(
            onGrantMicrophone: {
                PermissionService.requestMicrophone { _ in
                    self.appController.refreshPermissions(startup: false)
                }
                PermissionService.openMicrophoneSettings()
            },
            onGrantAccessibility: {
                PermissionService.requestAccessibilityPrompt()
                PermissionService.openAccessibilitySettings()
                self.appController.refreshPermissions(startup: false)
            },
            onGrantInputMonitoring: {
                PermissionService.requestInputMonitoringPrompt()
                PermissionService.openInputMonitoringSettings()
                self.appController.refreshPermissions(startup: false)
            },
            onRefresh: {
                self.appController.refreshPermissions(startup: false)
            }
        )
        .environmentObject(settings)
        .environmentObject(appState)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "FlashASR \u{6743}\u{9650}\u{8BBE}\u{7F6E}"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        permissionWindow = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.permissionGuideDismissed = true
            self?.permissionWindow = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.checkAndHideDock()
            }
        }
    }

    func showOnboarding() {
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
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let self else { return }
                self.checkAndHideDock()
                // After onboarding closes, check if permissions still need granting
                if self.settings.hasCompletedOnboarding {
                    self.appController.refreshPermissions(startup: false)
                }
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
