import Combine
import Foundation

struct CaptureUsage: Equatable {
    var mic: Bool
    var camera: Bool
}

enum CaptureActivityMapper {
    static let activityID = "capture"

    static func activity(micInUse: Bool, cameraInUse: Bool) -> IslandActivity? {
        guard micInUse || cameraInUse else { return nil }
        return IslandActivity(id: activityID, kind: .capture, priority: IslandActivity.Priority.capture,
                              detail: .capture(mic: micInUse, camera: cameraInUse))
    }
}

/// Publishes a "capture" activity while any app records with the microphone or camera.
@MainActor
final class CaptureActivitySource: ActivitySource {
    private let subject = CurrentValueSubject<[IslandActivity], Never>([])
    private var cancellable: AnyCancellable?

    var activitiesPublisher: AnyPublisher<[IslandActivity], Never> {
        subject.eraseToAnyPublisher()
    }

    init(usage: AnyPublisher<CaptureUsage, Never>) {
        cancellable = usage.removeDuplicates().sink { [weak self] usage in
            MainActor.assumeIsolated {
                let activity = CaptureActivityMapper.activity(micInUse: usage.mic, cameraInUse: usage.camera)
                self?.subject.send(activity.map { [$0] } ?? [])
            }
        }
    }
}
