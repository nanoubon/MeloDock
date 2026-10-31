import SwiftUI

/// Pure geometry for `ScrubRail`, kept separate so it can be unit tested.
enum ScrubRailMath {
    static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    /// Fraction of the rail under a horizontal location in the rail's own coordinates.
    static func fraction(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return clamped(Double(x / width))
    }

    /// Width of the filled part; a non-zero value never draws narrower than the rail is tall.
    static func filledWidth(fraction: Double, width: CGFloat, railHeight: CGFloat) -> CGFloat {
        let value = clamped(fraction)
        guard value > 0, width > 0 else { return 0 }
        return min(width, max(railHeight, width * CGFloat(value)))
    }

    /// Knob center, kept inside the rail so the knob is never cut off at either end.
    static func knobCenterX(fraction: Double, width: CGFloat, knobSize: CGFloat) -> CGFloat {
        let half = knobSize / 2
        guard width > knobSize else { return width / 2 }
        return min(max(half, width * CGFloat(clamped(fraction))), width - half)
    }

    /// One accessibility increment or decrement, clamped to 0...1.
    static func stepped(_ value: Double, by step: Double) -> Double {
        clamped(value + step)
    }
}

/// A thin capsule rail. With `onChange` it is a slider that shows a knob (and, unless `growsWhenActive` is off,
/// thickens) on hover or drag;
/// without it, it only displays a value.
struct ScrubRail: View {
    private enum Layout {
        static let railHeight: CGFloat = 4
        static let activeRailHeight: CGFloat = 6
        static let knobSize: CGFloat = 12
        static let accessibilityStep: Double = 0.05
    }

    let value: Double
    let fill: Color
    let accessibilityLabel: String
    let accessibilityValue: String
    var onChange: ((Double) -> Void)?
    var track: Color = IslandTheme.railTrack
    /// Whether the rail thickens on hover or drag; the knob still appears either way.
    var growsWhenActive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isDragging = false

    private var isActive: Bool {
        onChange != nil && (isHovering || isDragging)
    }

    var body: some View {
        if let onChange {
            rail
                .onHover { isHovering = $0 }
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: onChange(ScrubRailMath.stepped(value, by: Layout.accessibilityStep))
                    case .decrement: onChange(ScrubRailMath.stepped(value, by: -Layout.accessibilityStep))
                    @unknown default: break
                    }
                }
        } else {
            rail.accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var rail: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let railHeight = isActive && growsWhenActive ? Layout.activeRailHeight : Layout.railHeight

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(track)
                    .frame(height: railHeight)

                Capsule(style: .continuous)
                    .fill(fill)
                    .frame(
                        width: ScrubRailMath.filledWidth(fraction: value, width: width, railHeight: railHeight),
                        height: railHeight
                    )

                if onChange != nil {
                    Circle()
                        .fill(Color.white)
                        .frame(width: Layout.knobSize, height: Layout.knobSize)
                        .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                        .scaleEffect(isActive || reduceMotion ? 1 : 0.4)
                        .opacity(isActive ? 1 : 0)
                        .offset(x: ScrubRailMath.knobCenterX(
                            fraction: value, width: width, knobSize: Layout.knobSize
                        ) - Layout.knobSize / 2)
                }
            }
            .frame(width: width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width), including: onChange == nil ? .none : .all)
        }
        .animation(IslandTheme.railAnimation(reduceMotion: reduceMotion), value: isActive)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                isDragging = true
                onChange?(ScrubRailMath.fraction(atX: drag.location.x, width: width))
            }
            .onEnded { _ in
                isDragging = false
            }
    }
}
