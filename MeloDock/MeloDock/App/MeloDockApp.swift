import SwiftUI

@main
struct MeloDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container = DIContainer.shared

    var body: some Scene {
        Settings {
            SettingsView(viewModel: container.settingsViewModel)
                .frame(minWidth: 560, minHeight: 520)
        }
    }
}
