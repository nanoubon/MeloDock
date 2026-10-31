import SwiftUI

/// Presentation of one tab in the strip.
enum IslandTabInfo {
    static func title(_ kind: IslandActivity.Kind) -> String {
        switch kind {
        case .nowPlaying: "Music"
        case .timer: "Timer"
        case .calendar: "Calendar"
        default: ""
        }
    }
}

/// The expanded island: the current page above a strip of text tabs.
struct ExpandedContainerView: View {
    private enum Layout {
        static let tabHeight: CGFloat = 28
        static let tabGap: CGFloat = 4
        /// Each tab's text inset; the first tab hangs left by this much so its text lines up with the page.
        static let tabHorizontalPadding: CGFloat = 8
        /// Space between the tabs and the bottom of the shape. The 28pt tabs then rise 4pt into the page's
        /// bottom padding, as in the design.
        static let tabBottomInset: CGFloat = 8
    }

    @ObservedObject var coordinator: IslandCoordinator
    let viewModel: IslandViewModel
    let timerModel: TimerModel
    let calendarSource: CalendarActivitySource

    var body: some View {
        VStack(spacing: 0) {
            page
                .frame(width: IslandShapeMetrics.expandedSize.width, height: IslandShapeMetrics.pageHeight)
            // Declared after the page so it draws over the music page's artwork, which reaches down behind it.
            tabStrip
                .frame(width: IslandShapeMetrics.expandedSize.width, height: IslandShapeMetrics.tabStripHeight)
        }
    }

    @ViewBuilder
    private var page: some View {
        switch coordinator.currentPage {
        case .timer: TimerView(model: timerModel, onTextEditingChanged: { coordinator.setTextEditing($0) })
        case .calendar: CalendarEventView(source: calendarSource)
        default: ExpandedMusicView(viewModel: viewModel, topInset: coordinator.notch?.height ?? 0)
        }
    }

    private var tabStrip: some View {
        let current = coordinator.currentPage
        let stripHeight = IslandShapeMetrics.tabStripHeight
        return HStack(spacing: Layout.tabGap) {
            ForEach(coordinator.tabs, id: \.self) { kind in
                Button { coordinator.selectTab(kind) } label: {
                    Text(IslandTabInfo.title(kind))
                }
                .buttonStyle(IslandTabButtonStyle(isSelected: kind == current))
                .focusEffectDisabled()
                .accessibilityLabel("\(IslandTabInfo.title(kind)) tab")
                .accessibilityAddTraits(kind == current ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(height: Layout.tabHeight)
        // One leading edge on every page, so switching pages never moves the tabs under the pointer.
        .padding(.leading, ExpandedMusicView.textLeading - Layout.tabHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Centered in the strip the tabs would sit (stripHeight - tabHeight) / 2 above the bottom; move them so
        // they sit tabBottomInset above it instead.
        .offset(y: (stripHeight - Layout.tabHeight) / 2 - Layout.tabBottomInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Island pages")
    }
}

/// Text tab: dimmed until hovered or selected; the selected tab has a short accent underline.
private struct IslandTabButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        TabBody(configuration: configuration, isSelected: isSelected)
    }

    private struct TabBody: View {
        private enum Layout {
            static let height: CGFloat = 28
            static let horizontalPadding: CGFloat = 8
            static let cornerRadius: CGFloat = 6
            static let underlineHeight: CGFloat = 2
            static let underlineBottom: CGFloat = 2
        }

        let configuration: ButtonStyleConfiguration
        let isSelected: Bool

        @Environment(\.isFocused) private var isFocused
        @State private var isHovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
            configuration.label
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, Layout.horizontalPadding)
                .frame(height: Layout.height)
                .foregroundStyle(isSelected || isHovering ? IslandTheme.textPrimary : IslandTheme.textTertiary)
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: Layout.underlineHeight / 2, style: .continuous)
                        .fill(IslandTheme.accent)
                        .frame(height: Layout.underlineHeight)
                        .padding(.horizontal, Layout.horizontalPadding)
                        .padding(.bottom, Layout.underlineBottom)
                        .opacity(isSelected ? 1 : 0)
                }
                .overlay(shape.strokeBorder(IslandTheme.focusRing, lineWidth: 2).opacity(isFocused ? 1 : 0))
                .contentShape(shape)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.easeOut(duration: 0.12), value: isSelected)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}
