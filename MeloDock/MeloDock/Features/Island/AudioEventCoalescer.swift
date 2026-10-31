import Combine
import Foundation

/// Decides what a burst of hardware audio events needs. Volume events carry their value and never need an
/// enumeration; device-list and default-output changes do, and a burst of them needs only one.
enum AudioEventCoalescer {
    static let window: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(50)

    static func volume(in event: AudioDeviceEvent) -> Float? {
        if case .volumeChanged(let value) = event { return value }
        return nil
    }

    static func needsDeviceRefresh(_ batch: [AudioDeviceEvent]) -> Bool {
        batch.contains { volume(in: $0) == nil }
    }

    /// Emits once per `window` that contained at least one non-volume event.
    static func refreshTriggers<S: Scheduler>(
        _ events: AnyPublisher<AudioDeviceEvent, Never>,
        scheduler: S,
        window: S.SchedulerTimeType.Stride
    ) -> AnyPublisher<Void, Never> {
        events
            .filter { volume(in: $0) == nil }
            .collect(.byTime(scheduler, window))
            .filter(needsDeviceRefresh)
            .map { _ in () }
            .eraseToAnyPublisher()
    }
}
