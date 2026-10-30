import CoreGraphics

enum IslandMode: Equatable { case idle, compact, expanded }

enum IslandShapeMetrics {
    static let earWidth: CGFloat = 56
    /// Expanded content size; on a notched screen the shape is taller by the notch height.
    static let expandedSize = CGSize(width: 612, height: 188)
    static let pillSize = CGSize(width: 220, height: 34)

    static func size(for mode: IslandMode, notch: NotchGeometry?) -> CGSize {
        switch mode {
        case .idle:
            guard let notch else { return .zero }
            return CGSize(width: notch.width, height: notch.height)
        case .compact:
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
}
