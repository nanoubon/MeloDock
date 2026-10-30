import Foundation

/// Pure helpers for the timer page's inputs.
enum TimerInput {
    static let presetMinutes = [1, 5, 10, 25]
    static let maxMinutes = 999

    /// Whole minutes typed by the user (1...999) as seconds, or nil when empty or invalid.
    static func duration(fromMinutes text: String) -> TimeInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isASCII), trimmed.allSatisfy(\.isNumber),
              let minutes = Int(trimmed), (1...maxMinutes).contains(minutes) else { return nil }
        return TimeInterval(minutes * 60)
    }
}
