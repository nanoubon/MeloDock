import Foundation

/// A calendar event reduced to what the island shows.
struct CalendarEventInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let location: String?
    let joinURL: URL?
}

/// Pure rules for when a calendar event occupies the island: from 10 minutes before it starts
/// (inclusive) until 5 minutes after (exclusive).
enum CalendarWindow {
    static let leadTime: TimeInterval = 600
    static let tailTime: TimeInterval = 300

    /// The event to show at `now`; with overlaps the earliest start wins (ties by id).
    static func activeEvent(in events: [CalendarEventInfo], now: Date) -> CalendarEventInfo? {
        events
            .filter { now >= $0.start.addingTimeInterval(-leadTime) && now < $0.start.addingTimeInterval(tailTime) }
            .min { $0.start != $1.start ? $0.start < $1.start : $0.id < $1.id }
    }

    /// The next moment (strictly after `now`) at which some event enters or leaves its window.
    static func nextWakeDate(events: [CalendarEventInfo], now: Date) -> Date? {
        events
            .flatMap { [$0.start.addingTimeInterval(-leadTime), $0.start.addingTimeInterval(tailTime)] }
            .filter { $0 > now }
            .min()
    }

    private static let meetingHostSuffixes = ["zoom.us", "zoomgov.com", "meet.google.com", "teams.microsoft.com", "teams.live.com"]

    /// The first Zoom, Google Meet or Teams link found in the given texts (notes, location, URL), in order.
    static func joinURL(from texts: [String?]) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for text in texts.compactMap({ $0 }) where !text.isEmpty {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector?.matches(in: text, options: [], range: range) ?? [] {
                if let url = match.url, isMeetingLink(url) { return url }
            }
        }
        return nil
    }

    private static func isMeetingLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else { return false }
        return meetingHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
