import Combine
import Foundation

/// Shows the upcoming meeting in the island. Inert until calendar access is granted; never asks for it.
@MainActor
final class CalendarActivitySource: ActivitySource, ObservableObject {
    /// How far ahead events are fetched, and the longest the source goes without re-reading the store.
    static let lookahead: TimeInterval = 24 * 3600
    static let maxSleep: TimeInterval = 3600

    @Published private(set) var activeEvent: CalendarEventInfo?

    private let subject = CurrentValueSubject<[IslandActivity], Never>([])
    private let provider: CalendarEventProviding
    private let now: () -> Date
    private let scheduler: TransientScheduler
    private var statusCancellable: AnyCancellable?
    private var changesCancellable: AnyCancellable?
    private var wake: AnyCancellable?

    var activitiesPublisher: AnyPublisher<[IslandActivity], Never> {
        subject.removeDuplicates().eraseToAnyPublisher()
    }

    init(provider: CalendarEventProviding,
         now: @escaping () -> Date = Date.init,
         scheduler: @escaping TransientScheduler = IslandCoordinator.defaultScheduler) {
        self.provider = provider
        self.now = now
        self.scheduler = scheduler
        statusCancellable = provider.authorizationStatusPublisher
            .removeDuplicates()
            .sink { [weak self] status in
                MainActor.assumeIsolated { self?.statusChanged(status) }
            }
    }

    private func statusChanged(_ status: CalendarAuthorizationStatus) {
        if status == .authorized {
            changesCancellable = provider.changesPublisher.sink { [weak self] in
                MainActor.assumeIsolated { self?.refresh() }
            }
            refresh()
        } else {
            changesCancellable = nil
            wake = nil
            publish(nil)
        }
    }

    private func refresh() {
        let current = now()
        // Reach back past the tail so an event that started a moment ago is still seen.
        let events = provider.events(from: current.addingTimeInterval(-CalendarWindow.tailTime),
                                     to: current.addingTimeInterval(Self.lookahead))
        publish(CalendarWindow.activeEvent(in: events, now: current))
        let next = CalendarWindow.nextWakeDate(events: events, now: current)
        let delay = min(next.map { $0.timeIntervalSince(current) } ?? Self.maxSleep, Self.maxSleep)
        wake?.cancel()
        wake = scheduler(max(0, delay)) { [weak self] in self?.refresh() }
    }

    private func publish(_ event: CalendarEventInfo?) {
        if activeEvent != event { activeEvent = event }
        subject.send(event == nil ? [] : [IslandActivity(id: "calendar", kind: .calendar,
                                                         priority: IslandActivity.Priority.calendar, detail: .calendar)])
    }
}
