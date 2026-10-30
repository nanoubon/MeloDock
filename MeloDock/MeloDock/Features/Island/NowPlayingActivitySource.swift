import Combine
import Foundation

enum NowPlayingActivityMapper {
    static let pausedTimeout: TimeInterval = 300

    static func activity(for state: PlaybackState, pausedSince: Date?, now: Date) -> IslandActivity? {
        switch state.status {
        case .playing:
            return IslandActivity(id: "nowPlaying", kind: .nowPlaying,
                                  priority: IslandActivity.Priority.nowPlayingPlaying)
        case .paused:
            guard let pausedSince, now.timeIntervalSince(pausedSince) < pausedTimeout else { return nil }
            return IslandActivity(id: "nowPlaying", kind: .nowPlaying,
                                  priority: IslandActivity.Priority.nowPlayingPaused)
        case .stopped, .unavailable:
            return nil
        }
    }
}

@MainActor
final class NowPlayingActivitySource: ActivitySource {
    private let subject = CurrentValueSubject<[IslandActivity], Never>([])
    private let now: () -> Date
    private var latest: PlaybackState?
    private var pausedSince: Date?
    private var cancellable: AnyCancellable?
    private var timer: Timer?

    var activitiesPublisher: AnyPublisher<[IslandActivity], Never> {
        subject.eraseToAnyPublisher()
    }

    init(playbackStates: AnyPublisher<PlaybackState, Never>,
         now: @escaping () -> Date = Date.init,
         expiryInterval: TimeInterval = 15) {
        self.now = now
        cancellable = playbackStates.sink { [weak self] state in
            MainActor.assumeIsolated { self?.receive(state) }
        }
        let timer = Timer(timeInterval: expiryInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheck() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }

    func recheck() {
        guard let latest else {
            subject.send([])
            return
        }
        let activity = NowPlayingActivityMapper.activity(for: latest, pausedSince: pausedSince, now: now())
        subject.send(activity.map { [$0] } ?? [])
    }

    private func receive(_ state: PlaybackState) {
        if state.status == .paused {
            if latest?.status != .paused { pausedSince = now() }
        } else {
            pausedSince = nil
        }
        latest = state
        recheck()
    }
}
