import SwiftUI

struct SettingsView: View {
    var appController: AppController?
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        TabView {
            GeneralSettingsView(appController: appController)
                .tabItem { Label("\u{901A}\u{7528}", systemImage: "gear") }
                .environmentObject(settings)

            HotkeySettingsView(appController: appController)
                .tabItem { Label("\u{5FEB}\u{6377}\u{952E}", systemImage: "keyboard") }
                .environmentObject(settings)

            APIKeySettingsView()
                .tabItem { Label("API", systemImage: "key") }
                .environmentObject(settings)

            PromptSettingsView()
                .tabItem { Label("\u{63D0}\u{793A}\u{8BCD}", systemImage: "text.alignleft") }

            AboutView()
                .tabItem { Label("\u{5173}\u{4E8E}", systemImage: "info.circle") }
        }
        .frame(width: 600, height: 560)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.title.contains("\u{8BBE}\u{7F6E}") || window.contentView is NSHostingView<SettingsView>
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
