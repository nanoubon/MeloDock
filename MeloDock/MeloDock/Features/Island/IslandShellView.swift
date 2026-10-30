import SwiftUI

/// The island itself: a black notch-anchored shape that springs between idle, compact and expanded.
struct IslandShellView: View {
    private enum Layout {
        static let idleRadius: CGFloat = 8
        static let compactRadius: CGFloat = 12
        static let expandedRadius: CGFloat = 30
        static let edgeWidth: CGFloat = 1
    }

    private enum Theme {
        /// Opaque equivalent of white 8% over black, for the expanded island's bottom edge.
        static let expandedEdge = Color(white: 0.08)
        static let shadow = Color.black.opacity(0.4)
        static let shadowRadius: CGFloat = 14
        static let shadowY: CGFloat = 6
    }

    private enum Motion {
        static let expand = Animation.spring(response: 0.45, dampingFraction: 0.80)
        static let collapse = Animation.spring(response: 0.34, dampingFraction: 0.92)
        /// Idle and compact changes.
        static let compact = Animation.spring(response: 0.4, dampingFraction: 0.78)
        static let reduced = Animation.easeInOut(duration: 0.2)
        static let contentOut = Animation.easeOut(duration: 0.12)
        static let reducedContentOut = Animation.easeInOut(duration: 0.15)
    }

    @ObservedObject var coordinator: IslandCoordinator
    let viewModel: IslandViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The mode the shape last settled toward; tells a collapse apart from idle/compact changes.
    @State private var previousMode: IslandMode = .idle

    var body: some View {
        let mode = coordinator.mode
        let isExpanded = mode == .expanded
        let size = IslandShapeMetrics.size(for: mode, notch: coordinator.notch)
        let shape = NotchShape(bottomRadius: bottomRadius(for: mode))

        ZStack(alignment: .top) {
            // The black fill sits 1pt high, leaving a faint crescent along the bottom edge when expanded.
            shape.fill(isExpanded ? Theme.expandedEdge : Color.black)
            shape.fill(Color.black)
                .offset(y: -Layout.edgeWidth)
            content(for: mode)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        // The shadow is drawn by an unclipped copy of the shape behind the island.
        .background(
            shape.fill(Color.black)
                .shadow(color: isExpanded ? Theme.shadow : .clear,
                        radius: Theme.shadowRadius, x: 0, y: Theme.shadowY)
        )
        .contentShape(shape)
        // Compact and idle taps expand; expanded content keeps its own controls.
        .gesture(
            TapGesture().onEnded { coordinator.expand() },
            including: mode == .expanded ? .subviews : .all
        )
        .animation(shapeAnimation(to: mode), value: mode)
        .onChange(of: mode) { _, newMode in
            previousMode = newMode
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .colorScheme(.dark)
    }

    // Content is laid out at its final size so the animating shape reveals it rather than squeezing it.
    @ViewBuilder
    private func content(for mode: IslandMode) -> some View {
        switch mode {
        case .idle:
            EmptyView()
        case .compact:
            let size = IslandShapeMetrics.size(for: .compact, notch: coordinator.notch)
            CompactNowPlayingView(viewModel: viewModel)
                .frame(width: size.width, height: size.height)
                .transition(.opacity)
        case .expanded:
            ExpandedMusicView(viewModel: viewModel)
                .frame(width: IslandShapeMetrics.expandedSize.width, height: IslandShapeMetrics.expandedSize.height)
                // Keep the player clear of the physical notch.
                .padding(.top, coordinator.notch?.height ?? 0)
                // The player staggers its own fade-in; on collapse it fades out quickly as the shape closes.
                .transition(.asymmetric(
                    insertion: .identity,
                    removal: .opacity.animation(reduceMotion ? Motion.reducedContentOut : Motion.contentOut)
                ))
        }
    }

    /// Read while `previousMode` still holds the mode being left.
    private func shapeAnimation(to mode: IslandMode) -> Animation {
        if reduceMotion { return Motion.reduced }
        if mode == .expanded { return Motion.expand }
        if previousMode == .expanded { return Motion.collapse }
        return Motion.compact
    }

    private func bottomRadius(for mode: IslandMode) -> CGFloat {
        switch mode {
        case .idle: Layout.idleRadius
        case .compact: Layout.compactRadius
        case .expanded: Layout.expandedRadius
        }
    }
}
