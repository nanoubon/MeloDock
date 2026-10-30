import SwiftUI

/// Compact ears for the timer: glyph on the leading ear, remaining (or elapsed) time on the trailing ear.
struct CompactTimerView: View {
    @ObservedObject var model: TimerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let content = TimerEarsContent.make(countdown: model.countdown, stopwatch: model.stopwatch, now: context.date)
            let flashOff = content?.style == .finished && !reduceMotion && !TimerEarsContent.isFlashOn(at: context.date)
            HStack(spacing: 0) {
                Image(systemName: content?.style == .stopwatch ? "stopwatch.fill" : "timer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(content?.style == .finished ? Color.yellow : Color.orange)
                    .frame(width: IslandShapeMetrics.earWidth)
                Spacer(minLength: 0)
                Text(content?.text ?? "")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(IslandTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 4)
                    .frame(width: IslandShapeMetrics.earWidth)
            }
            .opacity(flashOff ? 0.25 : (content?.isPaused == true ? 0.6 : 1))
            .frame(maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.label(content))
        }
    }

    static func label(_ content: TimerEarsContent?) -> String {
        guard let content else { return "Timer" }
        switch content.style {
        case .finished: return "Timer done"
        case .countdown: return "Timer, \(content.text) remaining" + (content.isPaused ? ", paused" : "")
        case .stopwatch: return "Stopwatch, \(content.text)" + (content.isPaused ? ", paused" : "")
        }
    }
}

/// Compact ears for the upcoming calendar event: glyph on the leading ear, minutes to start or "Now" on the trailing ear.
struct CompactCalendarView: View {
    @ObservedObject var source: CalendarActivitySource

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let text = source.activeEvent.map { IslandTimeFormat.calendarEar(start: $0.start, now: context.date) } ?? ""
            HStack(spacing: 0) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: IslandShapeMetrics.earWidth)
                Spacer(minLength: 0)
                Text(text)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(IslandTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 4)
                    .frame(width: IslandShapeMetrics.earWidth)
            }
            .frame(maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text == "Now" ? "Calendar event starting now" : "Calendar event in \(text)")
        }
    }
}
