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

    static func symbol(_ kind: IslandActivity.Kind) -> String {
        switch kind {
        case .nowPlaying: "music.note"
        case .timer: "timer"
        case .calendar: "calendar"
        default: "circle"
        }
    }
}

/// The expanded island: the current page above a small tab strip.
struct ExpandedContainerView: View {
    @ObservedObject var coordinator: IslandCoordinator
    let viewModel: IslandViewModel
    let timerModel: TimerModel
    let calendarSource: CalendarActivitySource

    var body: some View {
        VStack(spacing: 0) {
            page
                .frame(width: IslandShapeMetrics.expandedSize.width, height: IslandShapeMetrics.pageHeight)
            tabStrip
                .frame(width: IslandShapeMetrics.expandedSize.width, height: IslandShapeMetrics.tabStripHeight)
        }
    }

    @ViewBuilder
    private var page: some View {
        switch coordinator.currentPage {
        case .timer: TimerView(model: timerModel)
        case .calendar: CalendarEventView(source: calendarSource)
        default: ExpandedMusicView(viewModel: viewModel)
        }
    }

    private var tabStrip: some View {
        let current = coordinator.currentPage
        return HStack(spacing: 8) {
            ForEach(coordinator.tabs, id: \.self) { kind in
                Button { coordinator.selectTab(kind) } label: {
                    Label(IslandTabInfo.title(kind), systemImage: IslandTabInfo.symbol(kind))
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(IslandChipButtonStyle(prominent: kind == current))
                .accessibilityLabel("\(IslandTabInfo.title(kind)) tab")
                .accessibilityAddTraits(kind == current ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Island pages")
    }
}
