import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let container = DIContainer.shared
    private var panelController: IslandPanelController?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureIslandPanel()
        configureStatusItem()
        configureHotkey()
        configureLaunchAtLoginSync()
        configureNotificationActions()

        Task { await container.islandViewModel.bootstrap() }

        if container.settingsStore.showOnStartup {
            panelController?.show()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { container.spotifyProvider.handleIncomingAuthURL($0) }
    }

    private func configureIslandPanel() {
        let islandView = IslandView(viewModel: container.islandViewModel)
        let controller = IslandPanelController(rootView: islandView)
        controller.onVisibilityChanged = { [weak self] visible in
            self?.container.settingsStore.overlayVisible = visible
        }
        panelController = controller
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "music.note.house", accessibilityDescription: "MeloDock")
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Overlay", action: #selector(toggleOverlay), keyEquivalent: "m"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit MeloDock", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        item.menu = menu
        statusItem = item
    }

    private func configureHotkey() {
        container.hotkeyService.onHotkeyPressed = { [weak self] in
            self?.toggleOverlay(nil)
        }

        container.hotkeyService.register(hotkey: container.settingsStore.hotkey)

        container.settingsStore.$hotkey
            .sink { [weak self] hotkey in
                self?.container.hotkeyService.register(hotkey: hotkey)
            }
            .store(in: &cancellables)
    }

    private func configureLaunchAtLoginSync() {
        container.settingsStore.$launchAtLogin
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.container.launchAtLoginService.setEnabled(enabled)
            }
            .store(in: &cancellables)
    }

    private func configureNotificationActions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleOverlayNotification(_:)),
            name: .meloDockToggleOverlay,
            object: nil
        )
    }

    @objc private func toggleOverlay(_ sender: Any?) {
        panelController?.toggle()
    }

    @objc private func handleToggleOverlayNotification(_ notification: Notification) {
        toggleOverlay(nil)
    }

    @objc private func openSettings(_ sender: Any?) {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let meloDockToggleOverlay = Notification.Name("com.nano.melodock.toggle-overlay")
}
