import Combine
import Foundation

/// Emits charging / low-battery transients; contributes no long-lived activities.
@MainActor
final class PowerActivitySource: ActivitySource {
    private let transientSubject = PassthroughSubject<IslandTransient, Never>()
    private var previous: PowerState?
    private var cancellable: AnyCancellable?

    var activitiesPublisher: AnyPublisher<[IslandActivity], Never> {
        Empty(completeImmediately: false).eraseToAnyPublisher()
    }

    var transientsPublisher: AnyPublisher<IslandTransient, Never> {
        transientSubject.eraseToAnyPublisher()
    }

    init(states: AnyPublisher<PowerState, Never>) {
        cancellable = states.sink { [weak self] state in
            MainActor.assumeIsolated { self?.receive(state) }
        }
    }

    private func receive(_ state: PowerState) {
        PowerEventMapper.events(from: previous, to: state).forEach(transientSubject.send)
        previous = state
    }
}
