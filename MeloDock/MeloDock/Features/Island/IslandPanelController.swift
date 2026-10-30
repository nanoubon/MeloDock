import AppKit
import Combine
import CoreGraphics
import SwiftUI

/// One transparent panel anchored at the notch that hosts the island shell.
/// Areas outside the island shape pass clicks through to the menu bar below.
@MainActor
final class IslandPanelController {
    private enum Layout {
        static let width: CGFloat = 640
        // Fits the tallest expanded shape (176 + notch height) with margin.
        static let height: CGFloat = 240
    }

    private let coordinator: IslandCoordinator
    private let panel: NSPanel
    private var cancellables = Set<AnyCancellable>()
    private var mouseMonitors: [Any] = []
    private var pointerInside = false
    private var didApplyInitialShowReposition = false

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
        updatePointer()
    }

    private func observeCoordinator() {
        // @Published emits before the property changes; hop to the next run loop pass so `mode` is current.
        Publishers.Merge4(
            coordinator.$selection.map { _ in () },
            coordinator.$isExpanded.map { _ in () },
            coordinator.$isIslandEnabled.map { _ in () },
            coordinator.$notch.map { _ in () }
        )
        .receive(on: RunLoop.main)
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
            panel.ignoresMouseEvents = true
            if pointerInside {
                pointerInside = false
                coordinator.pointerExited()
            }
            return
        }

        if !panel.isVisible {
            show()
        }
        updatePointer()
    }

    private func show() {
        panel.orderFrontRegardless()
        reposition()

        // First launch can report stale geometry; re-apply centering on next runloop ticks.
        if didApplyInitialShowReposition == false {
            didApplyInitialShowReposition = true

            DispatchQueue.main.async { [weak self] in
                self?.reposition()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.reposition()
            }
        }
    }

    // MARK: - Click-through and hover

    private func installMouseMonitors() {
        // A global monitor only sees events sent to other apps, so a local one covers our own panel.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updatePointer() }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    /// Lets clicks through outside the current island shape and reports hover transitions.
    private func updatePointer() {
        guard panel.isVisible else { return }

        let size = IslandShapeMetrics.size(for: coordinator.mode, notch: coordinator.notch)
        var hitRect = IslandShapeMetrics.hitRect(panelFrame: panel.frame, size: size)
        // The cursor can sit exactly on the screen's top edge, which `contains` treats as outside.
        hitRect.size.height += 1
        let inside = hitRect.contains(NSEvent.mouseLocation)

        panel.ignoresMouseEvents = !inside
        guard inside != pointerInside else { return }
        pointerInside = inside
        if inside {
            coordinator.pointerEntered()
        } else {
            coordinator.pointerExited()
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

        return NSScreen.main ?? screens.first
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
