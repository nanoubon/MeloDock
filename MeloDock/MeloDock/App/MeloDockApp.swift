import AppKit
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
        .commands {
            CommandMenu("MeloDock") {
                Button("Toggle Overlay") {
                    NotificationCenter.default.post(name: .meloDockToggleOverlay, object: nil)
                }
                .keyboardShortcut("m", modifiers: [.command, .option])

                Button("Open Settings") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
