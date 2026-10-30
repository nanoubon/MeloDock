import Combine

/// Feeds the island: long-lived activities plus short-lived transient notices.
@MainActor
protocol ActivitySource: AnyObject {
    var activitiesPublisher: AnyPublisher<[IslandActivity], Never> { get }
    var transientsPublisher: AnyPublisher<IslandTransient, Never> { get }
}

extension ActivitySource {
    var transientsPublisher: AnyPublisher<IslandTransient, Never> {
        Empty(completeImmediately: true).eraseToAnyPublisher()
    }
}
