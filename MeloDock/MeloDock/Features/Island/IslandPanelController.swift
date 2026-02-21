import AppKit
import SwiftUI

final class IslandPanelController {
    private let panel: NSPanel
    private let hostingController: NSHostingController<AnyView>
    var onVisibilityChanged: ((Bool) -> Void)?

    init<V: View>(rootView: V) {
        hostingController = NSHostingController(rootView: AnyView(rootView))
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentViewController = hostingController

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reposition),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        reposition()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
        onVisibilityChanged?(true)
    }

    func hide() {
        panel.orderOut(nil)
        onVisibilityChanged?(false)
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    @objc func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - panel.frame.width / 2.0
        let y = visibleFrame.maxY - panel.frame.height - 8.0
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
