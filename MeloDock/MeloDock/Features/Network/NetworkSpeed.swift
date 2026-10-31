import Foundation

/// Cumulative bytes one interface has received and sent. The system keeps these as 32-bit counters that wrap.
struct NetworkCounters: Equatable {
    var received: UInt32
    var sent: UInt32
}

/// Download and upload rates in bytes per second.
struct NetworkSpeed: Equatable {
    var download: Double
    var upload: Double

    static let zero = NetworkSpeed(download: 0, upload: 0)
}

enum NetworkSpeedCalculator {
    /// A jump this big in one sample is an interface that reset its counters, not traffic (2^31 bytes is 17 Gbit/s).
    /// A reset from a counter already above this threshold looks like a legitimate wrap and reads as one burst of
    /// traffic; that needs an interface recreated within a single sample and costs one second of a wrong number.
    static let resetThreshold: UInt32 = 1 << 31

    /// Rate from two samples of the same interfaces. Only interfaces present in both count, so one that appears or
    /// disappears between samples adds nothing; wrapped counters are handled, a reset counts as no traffic.
    static func speed(from previous: [String: NetworkCounters], to current: [String: NetworkCounters],
                      interval: TimeInterval) -> NetworkSpeed {
        guard interval > 0 else { return .zero }
        var received = 0.0
        var sent = 0.0
        for (name, now) in current {
            guard let before = previous[name] else { continue }
            received += Double(delta(from: before.received, to: now.received))
            sent += Double(delta(from: before.sent, to: now.sent))
        }
        return NetworkSpeed(download: received / interval, upload: sent / interval)
    }

    private static func delta(from old: UInt32, to new: UInt32) -> UInt32 {
        let difference = new &- old
        return difference >= resetThreshold ? 0 : difference
    }
}
