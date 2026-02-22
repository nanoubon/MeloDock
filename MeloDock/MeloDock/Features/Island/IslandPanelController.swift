import AppKit
import CoreGraphics
import QuartzCore
import SwiftUI

final class IslandPanelController {
    private enum Layout {
        static let width: CGFloat = 612
        static let height: CGFloat = 176
        static let cornerRadius: CGFloat = 26
        static let topPadding: CGFloat = 2
        static let horizontalPadding: CGFloat = 8
    }

    private let panel: NSPanel
    private let hostingController: NSHostingController<AnyView>
    private var didApplyInitialShowReposition = false
    var onVisibilityChanged: ((Bool) -> Void)?

    init<V: View>(rootView: V) {
        hostingController = NSHostingController(rootView: AnyView(rootView))
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .statusBar
        panel.isFloatingPanel = true
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
        panel.contentViewController = hostingController

        if let contentView = panel.contentView {
            configureLayerClipping(for: contentView)
        }

        configureLayerClipping(for: hostingController.view)
        applyShapeMask()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reposition),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reposition),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        reposition()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show() {
        panel.orderFrontRegardless()
        reposition()
        applyShapeMask()

        // First launch can report stale geometry; re-apply centering on next runloop ticks.
        if didApplyInitialShowReposition == false {
            didApplyInitialShowReposition = true

            DispatchQueue.main.async { [weak self] in
                self?.reposition()
                self?.applyShapeMask()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.reposition()
                self?.applyShapeMask()
            }
        }

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
        guard let screen = preferredScreen() else { return }

        let fallbackCenterX = screen.visibleFrame.midX
        let notchCenter = validatedNotchCenterX(for: screen, fallbackCenterX: fallbackCenterX)
        let centerX = notchCenter ?? fallbackCenterX
        let panelWidth = panel.frame.width > 0 ? panel.frame.width : Layout.width
        let panelHeight = panel.frame.height > 0 ? panel.frame.height : Layout.height
        let x = clamp(
            centerX - panelWidth / 2.0,
            min: screen.frame.minX + Layout.horizontalPadding,
            max: screen.frame.maxX - panelWidth - Layout.horizontalPadding
        )

        // On notched displays we anchor to the very top screen edge.
        // On non-notched displays we stay below the menu bar.
        let topReference = notchCenter != nil ? screen.frame.maxY : screen.visibleFrame.maxY
        let y = topReference - panelHeight - Layout.topPadding
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        applyShapeMask()
    }

    private func configureLayerClipping(for view: NSView) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }

        layer.backgroundColor = NSColor.clear.cgColor
        layer.masksToBounds = true
        layer.cornerRadius = Layout.cornerRadius
        if #available(macOS 10.15, *) {
            layer.cornerCurve = .continuous
        }
        layer.allowsEdgeAntialiasing = true
    }

    private func applyShapeMask() {
        guard let contentView = panel.contentView,
              let contentLayer = contentView.layer,
              let hostingLayer = hostingController.view.layer else {
            return
        }

        let bounds = contentView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let insetBounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = CGPath(
            roundedRect: insetBounds,
            cornerWidth: Layout.cornerRadius,
            cornerHeight: Layout.cornerRadius,
            transform: nil
        )

        let contentMask = CAShapeLayer()
        contentMask.frame = bounds
        contentMask.path = path
        contentMask.fillColor = NSColor.black.cgColor
        contentMask.contentsScale = panel.backingScaleFactor
        contentLayer.mask = contentMask

        let hostingMask = CAShapeLayer()
        hostingMask.frame = bounds
        hostingMask.path = path
        hostingMask.fillColor = NSColor.black.cgColor
        hostingMask.contentsScale = panel.backingScaleFactor
        hostingLayer.mask = hostingMask
    }

    private func preferredScreen() -> NSScreen? {
        let screens = NSScreen.screens

        if let notchedBuiltIn = screens.first(where: { $0.isBuiltInDisplay && notchCenterX(for: $0) != nil }) {
            return notchedBuiltIn
        }

        if let builtIn = screens.first(where: { $0.isBuiltInDisplay }) {
            return builtIn
        }

        return NSScreen.main ?? screens.first
    }

    private func notchCenterX(for screen: NSScreen) -> CGFloat? {
        if #available(macOS 12.0, *) {
            guard let rawLeft = screen.auxiliaryTopLeftArea,
                  let rawRight = screen.auxiliaryTopRightArea else {
                return nil
            }

            let left = normalizedAuxiliaryArea(rawLeft, on: screen)
            let right = normalizedAuxiliaryArea(rawRight, on: screen)

            guard !left.isEmpty, !right.isEmpty else { return nil }
            return (left.maxX + right.minX) / 2.0
        }
        return nil
    }

    private func validatedNotchCenterX(for screen: NSScreen, fallbackCenterX: CGFloat) -> CGFloat? {
        guard let notchCenter = notchCenterX(for: screen) else { return nil }

        // Defensive clamp: ignore obviously incorrect notch centers that can appear on first launch.
        let maxAllowedDeviation = max(60, screen.frame.width * 0.18)
        guard abs(notchCenter - fallbackCenterX) <= maxAllowedDeviation else {
            return nil
        }
        return notchCenter
    }

    private func normalizedAuxiliaryArea(_ rect: CGRect, on screen: NSScreen) -> CGRect {
        var normalized = rect
        let frame = screen.frame

        // Some configurations can report auxiliary areas in backing-space coordinates.
        let looksLikeBackingSpace = normalized.maxX > frame.maxX * 1.25 || normalized.width > frame.width * 1.25
        if looksLikeBackingSpace {
            normalized = screen.convertRectFromBacking(normalized)
        }

        // If coordinates are local to the screen (0...width), translate to global coordinates.
        let appearsLocalX = normalized.minX >= -1 && normalized.maxX <= frame.width + 1
        let appearsLocalY = normalized.minY >= -1 && normalized.maxY <= frame.height + 1
        if appearsLocalX && appearsLocalY {
            normalized = normalized.offsetBy(dx: frame.minX, dy: frame.minY)
        }

        return normalized
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
