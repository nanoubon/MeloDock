import Combine
import Foundation

enum TimerActivityMapper {
    static func activity(countdown: CountdownState, stopwatch: StopwatchState) -> IslandActivity? {
        var active = false
        switch countdown {
        case .running, .paused, .finished: active = true
        case .idle: break
        }
        if case .running = stopwatch { active = true }
        guard active else { return nil }
        return IslandActivity(id: "timer", kind: .timer, priority: IslandActivity.Priority.timer, detail: .timer)
    }
}

/// Shows the timer in the island while a countdown exists (running, paused or finished) or the stopwatch runs.
@MainActor
final class TimerActivitySource: ActivitySource {
    private let model: TimerModel
    private let subject = CurrentValueSubject<[IslandActivity], Never>([])
    private var cancellable: AnyCancellable?

    var activitiesPublisher: AnyPublisher<[IslandActivity], Never> {
        subject.removeDuplicates().eraseToAnyPublisher()
    }

    var transientsPublisher: AnyPublisher<IslandTransient, Never> { model.transientsPublisher }

    init(model: TimerModel) {
        self.model = model
        cancellable = Publishers.CombineLatest(model.$countdown, model.$stopwatch)
            .sink { [weak self] countdown, stopwatch in
                let activity = TimerActivityMapper.activity(countdown: countdown, stopwatch: stopwatch)
                self?.subject.send(activity.map { [$0] } ?? [])
            }
    }
}
