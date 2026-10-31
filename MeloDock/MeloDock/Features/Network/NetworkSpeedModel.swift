import Combine
import Foundation

/// Samples the interface counters once a second while running and publishes the resulting rates.
/// The speed is deliberately not part of an `IslandActivity`: the coordinator must not re-rank every second.
@MainActor
final class NetworkSpeedModel: ObservableObject {
    static let sampleInterval: TimeInterval = 1

    @Published private(set) var speed = NetworkSpeed.zero
    private(set) var isRunning = false

    private let reader: NetworkCounterReading
    private let now: () -> Date
    private var timer: Timer?
    private var previous: (counters: [String: NetworkCounters], at: Date)?

    init(reader: NetworkCounterReading = SystemNetworkCounterReader(), now: @escaping () -> Date = Date.init) {
        self.reader = reader
        self.now = now
    }

    deinit { timer?.invalidate() }

    /// Starting takes a baseline sample, so the first rate appears one interval later (zero until then).
    func setRunning(_ running: Bool) {
        guard running != isRunning else { return }
        isRunning = running
        if running {
            sample()
            let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
            previous = nil
            speed = .zero
        }
    }

    /// One sample; the timer calls this, and tests call it directly with a fake clock.
    func sample() {
        let current = reader.read()
        let time = now()
        if let previous {
            let next = NetworkSpeedCalculator.speed(from: previous.counters, to: current,
                                                    interval: time.timeIntervalSince(previous.at))
            if next != speed { speed = next }
        }
        previous = (current, time)
    }
}
