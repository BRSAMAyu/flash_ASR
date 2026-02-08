import SwiftUI

@main
struct FlashASRApp: App {
    @NSApplicationDelegateAdaptor(FlashASRDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(delegate.appState)
                .environmentObject(delegate.settings)
        } label: {
            MenuBarLabel(appState: delegate.appState)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(appController: delegate.appController)
                .environmentObject(delegate.settings)
                .environmentObject(delegate.appState)
        }
    }
}
