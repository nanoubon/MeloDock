import Foundation

/// Pure text helpers for the timer and calendar ears.
enum IslandTimeFormat {
    /// `m:ss`, or `h:mm:ss` from one hour up. Negative values read as zero; fractions are dropped.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Whole minutes until `start`, rounded up so "9m" holds until exactly nine minutes remain; zero once started.
    static func minutesUntil(_ start: Date, now: Date) -> Int {
        let seconds = start.timeIntervalSince(now)
        return seconds <= 0 ? 0 : Int((seconds / 60).rounded(.up))
    }

    /// Calendar ear text: "Now" once the event has started, otherwise "5m".
    static func calendarEar(start: Date, now: Date) -> String {
        let minutes = minutesUntil(start, now: now)
        return minutes == 0 ? "Now" : "\(minutes)m"
    }
}

/// What the timer ears show: the countdown when one exists, otherwise the running stopwatch.
struct TimerEarsContent: Equatable {
    enum Style: Equatable { case countdown, stopwatch, finished }

    let style: Style
    let text: String
    /// Finished countdowns flash; paused ones are dimmed.
    let isPaused: Bool

    static func make(countdown: CountdownState, stopwatch: StopwatchState, now: Date) -> TimerEarsContent? {
        switch countdown {
        case .running(let endsAt):
            let remaining = max(0, endsAt.timeIntervalSince(now))
            return TimerEarsContent(style: .countdown, text: IslandTimeFormat.clock(remaining.rounded(.up)), isPaused: false)
        case .paused(let remaining):
            return TimerEarsContent(style: .countdown, text: IslandTimeFormat.clock(remaining.rounded(.up)), isPaused: true)
        case .finished:
            return TimerEarsContent(style: .finished, text: "Done", isPaused: false)
        case .idle:
            break
        }
        switch stopwatch {
        case .running(let startedAt, let accumulated):
            let elapsed = accumulated + max(0, now.timeIntervalSince(startedAt))
            return TimerEarsContent(style: .stopwatch, text: IslandTimeFormat.clock(elapsed), isPaused: false)
        case .paused(let elapsed):
            return TimerEarsContent(style: .stopwatch, text: IslandTimeFormat.clock(elapsed), isPaused: true)
        case .idle:
            return nil
        }
    }

    /// Finished ears blink once per second.
    static func isFlashOn(at date: Date) -> Bool {
        Int(date.timeIntervalSinceReferenceDate.rounded(.down)) % 2 == 0
    }
}
