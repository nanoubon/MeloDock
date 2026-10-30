import AppKit
import SwiftUI

/// Expanded calendar page: the upcoming (or just-started) event with a Join button when it has a meeting link.
struct CalendarEventView: View {
    @ObservedObject var source: CalendarActivitySource

    var body: some View {
        Group {
            if let event = source.activeEvent {
                eventBody(event)
            } else {
                Text("No upcoming event")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(IslandTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(IslandTheme.textPrimary)
    }

    private func eventBody(_ event: CalendarEventInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Label(IslandTimeFormat.calendarEar(start: event.start, now: context.date) == "Now"
                      ? "Now" : "In \(IslandTimeFormat.calendarEar(start: event.start, now: context.date))",
                      systemImage: "calendar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.red)
            }
            Text(event.title)
                .font(.system(size: 22, weight: .semibold))
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            Text("\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(IslandTheme.textSecondary)
            if let location = event.location, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 13))
                    .foregroundStyle(IslandTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let url = event.joinURL {
                Button { NSWorkspace.shared.open(url) } label: { Label("Join", systemImage: "video.fill") }
                    .buttonStyle(IslandChipButtonStyle(prominent: true))
                    .accessibilityLabel("Join meeting \(event.title)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
