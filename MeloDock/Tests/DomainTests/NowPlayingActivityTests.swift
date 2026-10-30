#if canImport(XCTest)
import XCTest
import Combine
@testable import MeloDock

@MainActor
final class NowPlayingActivityTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func state(_ status: PlaybackStatus) -> PlaybackState {
        PlaybackState(provider: .appleMusic, status: status, track: nil, message: nil)
    }

    func testPlayingIsPriority60() {
        let a = NowPlayingActivityMapper.activity(for: state(.playing), pausedSince: nil, now: t0)
        XCTAssertEqual(a, IslandActivity(id: "nowPlaying", kind: .nowPlaying, priority: IslandActivity.Priority.nowPlayingPlaying))
        XCTAssertEqual(a?.priority, 60)
    }

    func testPausedWithinTimeoutIsPriority20() {
        let a = NowPlayingActivityMapper.activity(for: state(.paused), pausedSince: t0, now: t0.addingTimeInterval(299))
        XCTAssertEqual(a?.priority, IslandActivity.Priority.nowPlayingPaused)
        XCTAssertEqual(a?.id, "nowPlaying")
    }

    func testPausedAtTimeoutIsNil() {
        XCTAssertNil(NowPlayingActivityMapper.activity(for: state(.paused), pausedSince: t0, now: t0.addingTimeInterval(300)))
    }

    func testStoppedAndUnavailableAreNil() {
        XCTAssertNil(NowPlayingActivityMapper.activity(for: state(.stopped), pausedSince: nil, now: t0))
        XCTAssertNil(NowPlayingActivityMapper.activity(for: state(.unavailable), pausedSince: nil, now: t0))
    }

    private var clock = Date(timeIntervalSince1970: 1_000_000)
    private var subject = PassthroughSubject<PlaybackState, Never>()
    private var emissions: [[IslandActivity]] = []
    private var cancellable: AnyCancellable?
    private var source: NowPlayingActivitySource!

    override func setUp() {
        super.setUp()
        clock = Date(timeIntervalSince1970: 1_000_000)
        subject = PassthroughSubject<PlaybackState, Never>()
        emissions = []
        source = NowPlayingActivitySource(
            playbackStates: subject.eraseToAnyPublisher(),
            now: { [unowned self] in self.clock },
            expiryInterval: 3600
        )
        cancellable = source.activitiesPublisher.sink { [unowned self] in self.emissions.append($0) }
    }

    override func tearDown() {
        cancellable = nil
        source = nil
        super.tearDown()
    }

    private func send(_ status: PlaybackStatus) {
        subject.send(PlaybackState(provider: .appleMusic, status: status, track: nil, message: nil))
    }

    func testPausedExpiresAfterRecheck() {
        send(.paused)
        XCTAssertEqual(emissions.last?.count, 1)
        clock = clock.addingTimeInterval(301)
        source.recheck()
        XCTAssertEqual(emissions.last, [])
    }

    func testResumeAndRepauseRestartsClock() {
        send(.paused)
        clock = clock.addingTimeInterval(200)
        send(.playing)
        clock = clock.addingTimeInterval(50)
        send(.paused)
        clock = clock.addingTimeInterval(150)
        source.recheck()
        XCTAssertEqual(emissions.last?.first?.priority, IslandActivity.Priority.nowPlayingPaused)
    }

    // Providers re-send `.paused` on every poll; that must not restart the 5-minute clock.
    func testRepeatedPausedDoesNotResetClock() {
        send(.paused)
        clock = clock.addingTimeInterval(200)
        send(.paused)
        clock = clock.addingTimeInterval(150)
        source.recheck()
        XCTAssertEqual(emissions.last, [])
    }

    func testPlayingEmitsNowPlayingAtPriority60() {
        send(.playing)
        XCTAssertEqual(emissions.last, [IslandActivity(id: "nowPlaying", kind: .nowPlaying, priority: 60)])
    }

    func testStoppedEmitsNothing() {
        send(.playing)
        send(.stopped)
        XCTAssertEqual(emissions.last, [])
    }
}
#endif
