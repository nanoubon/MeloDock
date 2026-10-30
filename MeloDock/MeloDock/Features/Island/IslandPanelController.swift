import AppKit
import Combine
import CoreGraphics
import SwiftUI

/// One transparent panel anchored at the notch that hosts the island shell.
/// Areas outside the island shape pass clicks through to the menu bar below.
@MainActor
final class IslandPanelController {
    private enum Layout {
        static let width: CGFloat = IslandShapeMetrics.panelWidth
        // Fits the tallest expanded shape (188 + notch height) plus its drop shadow.
        static let height: CGFloat = 260
    }

    private let coordinator: IslandCoordinator
    private let panel: NSPanel
    private var cancellables = Set<AnyCancellable>()
    private var mouseMonitors: [Any] = []
    /// Last hover state reported to the coordinator; changes only on real mouse movement (or an exit).
    private var pointerInside = false

    init(coordinator: IslandCoordinator, viewModel: IslandViewModel) {
        self.coordinator = coordinator
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Setting isFloatingPanel resets the level to .floating, so it must come before `level`.
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .utilityWindow
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true

        let hostingView = NSHostingView(rootView: IslandShellView(coordinator: coordinator, viewModel: viewModel))
        // The panel keeps a fixed size; the island shape animates inside it.
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height)
        panel.contentView = hostingView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reposition),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(reposition),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        installMouseMonitors()
        observeCoordinator()
        reposition()

        // Launch can report stale or missing notch geometry; re-check on the next runloop ticks,
        // even while the panel is hidden, so an idle notch island still appears.
        DispatchQueue.main.async { [weak self] in
            self?.reposition()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.reposition()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }
    }

    @objc private func reposition() {
        guard let screen = preferredScreen() else { return }

        let fallbackCenterX = screen.visibleFrame.midX
        let notch = notchGeometry(for: screen)
        if notch != coordinator.notch {
            coordinator.updateNotch(notch)
        }

        let centerX = notch?.centerX ?? fallbackCenterX
        let x = clamp(
            centerX - Layout.width / 2,
            min: screen.frame.minX,
            max: screen.frame.maxX - Layout.width
        )

        // On notched displays we anchor to the very top screen edge.
        // On non-notched displays we stay below the menu bar.
        let topReference = notch != nil ? screen.frame.maxY : screen.visibleFrame.maxY
        panel.setFrameOrigin(NSPoint(x: x, y: topReference - Layout.height))
        refreshAfterLayoutChange()
    }

    private func observeCoordinator() {
        // @Published emits before the property changes; hop to the main queue so `mode` is current.
        Publishers.Merge5(
            coordinator.$selection.map { _ in () },
            coordinator.$transient.map { _ in () },
            coordinator.$isExpanded.map { _ in () },
            coordinator.$isIslandEnabled.map { _ in () },
            coordinator.$notch.map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            self?.updateVisibility()
        }
        .store(in: &cancellables)
    }

    private func updateVisibility() {
        let hidden = (coordinator.mode == .idle && coordinator.notch == nil)
            || (!coordinator.isIslandEnabled && !coordinator.isExpanded)

        if hidden {
            panel.orderOut(nil)
            setIgnoresMouseEvents(true)
            if pointerInside {
                pointerInside = false
                coordinator.pointerExited()
            }
            return
        }

        if !panel.isVisible {
            panel.orderFrontRegardless()
            reposition()
        }
        refreshAfterLayoutChange()
    }

    // MARK: - Click-through and hover

    private func installMouseMonitors() {
        // A global monitor only sees events sent to other apps, so a local one covers our own panel.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouseMoved() }
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouseMoved() }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    /// Real mouse movement: refreshes click-through and reports hover transitions.
    private func handleMouseMoved() {
        guard panel.isVisible else { return }

        let inside = refreshClickThrough()
        guard inside != pointerInside else { return }
        pointerInside = inside
        if inside {
            coordinator.pointerEntered()
        } else {
            coordinator.pointerExited()
        }
    }

    /// The shape or panel moved under a still cursor. Only an exit is reported, so ears
    /// appearing under a resting cursor do not count as a hover.
    private func refreshAfterLayoutChange() {
        guard panel.isVisible else { return }

        let inside = refreshClickThrough()
        if !inside && pointerInside {
            pointerInside = false
            coordinator.pointerExited()
        }
    }

    /// Lets clicks through outside the current island shape and secondary circle; returns whether the cursor is inside it.
    private func refreshClickThrough() -> Bool {
        let size = IslandShapeMetrics.size(for: coordinator.mode, notch: coordinator.notch)
        var hitRect = IslandShapeMetrics.hitRect(panelFrame: panel.frame, size: size)
        // The cursor can sit exactly on the screen's top edge, which `contains` treats as outside.
        hitRect.size.height += 1
        let mouse = NSEvent.mouseLocation
        let inside = hitRect.contains(mouse)
        // The secondary circle takes clicks but does not count as hovering the island.
        var overCircle = false
        if var circle = IslandShapeMetrics.secondaryFrame(
            panelFrame: panel.frame, mode: coordinator.mode, notch: coordinator.notch,
            hasSecondary: coordinator.selection.secondary != nil) {
            circle.size.height += 1
            overCircle = circle.contains(mouse)
        }
        setIgnoresMouseEvents(!(inside || overCircle))
        return inside
    }

    private func setIgnoresMouseEvents(_ ignores: Bool) {
        if panel.ignoresMouseEvents != ignores {
            panel.ignoresMouseEvents = ignores
        }
    }

    // MARK: - Screen selection

    private func preferredScreen() -> NSScreen? {
        let screens = NSScreen.screens

        if let notchedBuiltIn = screens.first(where: { $0.isBuiltInDisplay && notchGeometry(for: $0) != nil }) {
            return notchedBuiltIn
        }

        if let builtIn = screens.first(where: { $0.isBuiltInDisplay }) {
            return builtIn
        }

        // Lid closed: the primary (menu-bar) display, not the key window's screen.
        return screens.first ?? NSScreen.main
    }

    private func notchGeometry(for screen: NSScreen) -> NotchGeometry? {
        NotchGeometry.make(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            backingScale: screen.backingScaleFactor,
            auxLeft: screen.auxiliaryTopLeftArea,
            auxRight: screen.auxiliaryTopRightArea,
            fallbackCenterX: screen.visibleFrame.midX
        )
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.max(minValue, Swift.min(value, maxValue))
    }
}

private extension NSScreen {
    var isBuiltInDisplay: Bool {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }
}
