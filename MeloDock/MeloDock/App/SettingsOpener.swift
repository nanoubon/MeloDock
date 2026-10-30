import AppKit

/// Single entry point for opening the Settings window (status menu, command menu).
///
/// `NSApp.sendAction(showSettingsWindow:)` reports success but opens nothing on current macOS
/// (the SwiftUI `Settings` scene is opened by the app menu's own callback item), so we trigger
/// that item directly.
@MainActor
enum SettingsOpener {
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        if let menu = NSApp.mainMenu?.items.first?.submenu, let item = settingsItem(in: menu) {
            menu.performActionForItem(at: menu.index(of: item))
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    /// The Cmd+, item SwiftUI adds to the application menu; matched by key equivalent, not title (localized).
    static func settingsItem(in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask.contains(.command) && !$0.isSeparatorItem }
    }
}
