import SwiftUI

struct SettingsView: View {
    var appController: AppController?
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
                .environmentObject(settings)

            HotkeySettingsView(appController: appController)
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
                .environmentObject(settings)

            APIKeySettingsView()
                .tabItem { Label("API", systemImage: "key") }
                .environmentObject(settings)

            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 380)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.title.contains("Settings") || window.contentView is NSHostingView<SettingsView>
            else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let visibleWindows = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) && $0.level == .normal }
                if visibleWindows.isEmpty {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
}
