import Combine
import Foundation

/// Keeps the network speed in the island as the lowest-priority activity, so it fills the ears whenever nothing
/// else does. Sampling runs only while the Settings switch is on; the coordinator's kind filter does the showing.
@MainActor
final class NetworkActivitySource: ActivitySource {
    static let activity = IslandActivity(id: "network", kind: .network,
                                         priority: IslandActivity.Priority.network, detail: .network)

    private var cancellable: AnyCancellable?

    var activitiesPublisher: AnyPublisher<[IslandActivity], Never> {
        Just([Self.activity]).eraseToAnyPublisher()
    }

    init(model: NetworkSpeedModel, isEnabled: AnyPublisher<Bool, Never>) {
        cancellable = isEnabled
            .removeDuplicates()
            .sink { [weak model] enabled in model?.setRunning(enabled) }
    }
}
