import CoreGraphics

enum IslandMode: Equatable { case idle, compact, transient, expanded }

enum IslandShapeMetrics {
    static let earWidth: CGFloat = 56
    /// Expanded content size; on a notched screen the shape is taller by the notch height.
    static let expandedSize = CGSize(width: 612, height: 188)
    static let pillSize = CGSize(width: 220, height: 34)
    /// Width of the fixed-size island panel; the shape and the secondary circle must fit inside it.
    static let panelWidth: CGFloat = 640
    /// Space between the island's trailing edge and the secondary circle.
    static let secondaryGap: CGFloat = 8

    static func size(for mode: IslandMode, notch: NotchGeometry?) -> CGSize {
        switch mode {
        case .idle:
            guard let notch else { return .zero }
            return CGSize(width: notch.width, height: notch.height)
        case .compact, .transient:
            guard let notch else { return pillSize }
            return CGSize(width: notch.width + 2 * earWidth, height: notch.height)
        case .expanded:
            // The content sits below the notch, so the shape grows by its height.
            return CGSize(width: expandedSize.width, height: expandedSize.height + (notch?.height ?? 0))
        }
    }

    /// `size` centered horizontally on the panel and flush with its top edge (maxY).
    static func hitRect(panelFrame: CGRect, size: CGSize) -> CGRect {
        CGRect(x: panelFrame.midX - size.width / 2,
               y: panelFrame.maxY - size.height,
               width: size.width, height: size.height)
    }

    /// Diameter of the secondary circle: it matches the collapsed island's height.
    static func secondaryCircleSize(notch: NotchGeometry?) -> CGFloat {
        size(for: .compact, notch: notch).height
    }

    /// Where the secondary circle sits, in screen coordinates, or nil when it is not shown.
    /// It appears only beside the collapsed island (compact or transient) and only when there is a second activity.
    static func secondaryFrame(panelFrame: CGRect, mode: IslandMode, notch: NotchGeometry?,
                               hasSecondary: Bool) -> CGRect? {
        guard hasSecondary, mode == .compact || mode == .transient else { return nil }
        let island = hitRect(panelFrame: panelFrame, size: size(for: mode, notch: notch))
        let diameter = secondaryCircleSize(notch: notch)
        return CGRect(x: island.maxX + secondaryGap, y: island.maxY - diameter, width: diameter, height: diameter)
    }
}
