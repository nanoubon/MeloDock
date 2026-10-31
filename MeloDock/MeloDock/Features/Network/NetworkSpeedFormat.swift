import Foundation

/// Pure text helpers for the network speed ears. Units are bytes per second in powers of 1000, as Finder shows sizes.
enum NetworkSpeedFormat {
    private static let shortUnits = ["B", "K", "M", "G"]
    private static let spokenUnits = ["bytes", "kilobytes", "megabytes", "gigabytes"]

    /// Compact text that fits an ear: `0`, `850B`, `1.2K`, `12K`, `1.2M`, `1.1G`.
    static func short(_ bytesPerSecond: Double) -> String {
        let (value, unit) = scaled(bytesPerSecond)
        if value < 0.5 { return "0" }
        return number(value, unit: unit) + shortUnits[unit]
    }

    /// Full wording for VoiceOver: `1.2 megabytes per second`.
    static func spoken(_ bytesPerSecond: Double) -> String {
        let (value, unit) = scaled(bytesPerSecond)
        return number(value, unit: unit) + " " + spokenUnits[unit] + " per second"
    }

    /// The value in the largest unit that keeps it under 1000 once rounded, so 999.6K reads "1.0M" and never "1000K".
    private static func scaled(_ bytesPerSecond: Double) -> (value: Double, unit: Int) {
        var value = bytesPerSecond.isFinite ? max(0, bytesPerSecond) : 0
        var unit = 0
        while value >= 999.5 && unit < shortUnits.count - 1 {
            value /= 1000
            unit += 1
        }
        return (value, unit)
    }

    /// Bytes are whole numbers; larger units keep one decimal below 10 ("1.2M", "12M").
    private static func number(_ value: Double, unit: Int) -> String {
        if unit == 0 || value >= 9.95 { return String(Int(value.rounded())) }
        return String(format: "%.1f", value)
    }
}
