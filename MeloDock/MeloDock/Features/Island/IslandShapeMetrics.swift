import CoreGraphics

enum IslandMode: Equatable { case idle, compact, transient, expanded }

enum IslandShapeMetrics {
    static let earWidth: CGFloat = 56
    /// Height of the page (player, timer or event) in the expanded island.
    static let pageHeight: CGFloat = 188
    /// Height of the tab strip under the page.
    static let tabStripHeight: CGFloat = 32
    /// Expanded content size; on a notched screen the shape is taller by the notch height.
    static let expandedSize = CGSize(width: 612, height: pageHeight + tabStripHeight)
    /// Height of the fixed-size island panel: the tallest expanded shape (a 44pt notch is the largest expected)
    /// plus room for its drop shadow.
    static let panelHeight: CGFloat = 300
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

    /// Ear width while a transient shows. Notices carrying a device name get wider ears so long Bluetooth and
    /// output names are not cut off; every other notice keeps the standard ear.
    static let nameEarWidth: CGFloat = 100

    static func transientEarWidth(for payload: IslandTransient.Payload?) -> CGFloat {
        switch payload {
        case .bluetooth, .output: nameEarWidth
        default: earWidth
        }
    }

    /// Like `size(for:notch:)`, but a transient showing a name payload widens both ears (the shape stays centered
    /// on the notch). `transient` is ignored outside `.transient` mode.
    static func size(for mode: IslandMode, notch: NotchGeometry?, transient: IslandTransient.Payload?,
                     compactEarWidth: CGFloat = earWidth) -> CGSize {
        var base = size(for: mode, notch: notch)
        if mode == .transient {
            base.width += 2 * (transientEarWidth(for: transient) - earWidth)
        } else if mode == .compact, notch != nil {
            // The pill under a notchless menu bar has a fixed width, so only the notch's ears grow.
            base.width += 2 * (compactEarWidth - earWidth)
        }
        return base
    }

    /// Ear width while music shares the collapsed island with the network speed: the leading ear holds the artwork
    /// and the spectrum, so both ears grow (the shape stays centered on the notch).
    static let musicNetworkEarWidth: CGFloat = 76

    static func compactEarWidth(primary: IslandActivity?, networkEnabled: Bool) -> CGFloat {
        primary?.kind == .nowPlaying && networkEnabled ? musicNetworkEarWidth : earWidth
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
                               hasSecondary: Bool, transient: IslandTransient.Payload? = nil,
                               compactEarWidth: CGFloat = earWidth) -> CGRect? {
        guard hasSecondary, mode == .compact || mode == .transient else { return nil }
        let island = hitRect(panelFrame: panelFrame,
                             size: size(for: mode, notch: notch, transient: transient,
                                        compactEarWidth: compactEarWidth))
        let diameter = secondaryCircleSize(notch: notch)
        return CGRect(x: island.maxX + secondaryGap, y: island.maxY - diameter, width: diameter, height: diameter)
    }
}
