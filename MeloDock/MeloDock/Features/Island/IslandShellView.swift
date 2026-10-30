import SwiftUI

/// The island itself: a black notch-anchored shape that springs between idle, compact and expanded.
struct IslandShellView: View {
    private enum Layout {
        static let idleRadius: CGFloat = 8
        static let compactRadius: CGFloat = 12
        static let expandedRadius: CGFloat = 26
    }

    @ObservedObject var coordinator: IslandCoordinator
    let viewModel: IslandViewModel

    var body: some View {
        let mode = coordinator.mode
        let size = IslandShapeMetrics.size(for: mode, notch: coordinator.notch)
        let shape = NotchShape(bottomRadius: bottomRadius(for: mode))

        ZStack(alignment: .top) {
            shape.fill(Color.black)
            content(for: mode)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .contentShape(shape)
        // Compact and idle taps expand; expanded content keeps its own controls.
        .gesture(
            TapGesture().onEnded { coordinator.toggleExpanded() },
            including: mode == .expanded ? .subviews : .all
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: mode)
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
                .transition(.opacity)
        }
    }

    private func bottomRadius(for mode: IslandMode) -> CGFloat {
        switch mode {
        case .idle: Layout.idleRadius
        case .compact: Layout.compactRadius
        case .expanded: Layout.expandedRadius
        }
    }
}
