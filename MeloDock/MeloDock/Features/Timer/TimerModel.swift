import AppKit
import Combine
import Foundation

enum CountdownState: Equatable {
    case idle
    case running(endsAt: Date)
    case paused(remaining: TimeInterval)
    case finished(at: Date)
}

enum StopwatchState: Equatable {
    case idle
    case running(startedAt: Date, accumulated: TimeInterval)
    case paused(elapsed: TimeInterval)
}

/// One countdown and one stopwatch, kept in memory only. Time comes from an injected clock and `tick(now:)`;
/// a real 1s ticker runs in production only while something needs it.
@MainActor
final class TimerModel: ObservableObject {
    static let soundInterval: TimeInterval = 3
    static let soundDuration: TimeInterval = 30
    static let transientDuration: TimeInterval = 2.5

    @Published private(set) var countdown: CountdownState = .idle
    @Published private(set) var stopwatch: StopwatchState = .idle
    /// Length of the current countdown, for progress display. Zero when idle.
    @Published private(set) var countdownDuration: TimeInterval = 0
    /// Last time seen by `tick`; views observe it to refresh once a second.
    @Published private(set) var tickDate: Date

    private let transientSubject = PassthroughSubject<IslandTransient, Never>()
    var transientsPublisher: AnyPublisher<IslandTransient, Never> { transientSubject.eraseToAnyPublisher() }

    private let now: () -> Date
    private let playSound: () -> Void
    private let startsTicker: Bool
    private var ticker: Timer?
    private var lastSoundAt: Date?

    init(now: @escaping () -> Date = Date.init,
         playSound: @escaping () -> Void = { NSSound.beep() },
         startsTicker: Bool = true) {
        self.now = now
        self.playSound = playSound
        self.startsTicker = startsTicker
        tickDate = now()
    }

    deinit {
        ticker?.invalidate()
    }

    // MARK: Countdown

    func startCountdown(duration: TimeInterval) {
        guard duration > 0 else { return }
        lastSoundAt = nil
        countdownDuration = duration
        countdown = .running(endsAt: now().addingTimeInterval(duration))
        updateTicker()
    }

    func pauseCountdown() {
        guard case .running(let endsAt) = countdown else { return }
        countdown = .paused(remaining: max(0, endsAt.timeIntervalSince(now())))
        updateTicker()
    }

    func resumeCountdown() {
        guard case .paused(let remaining) = countdown else { return }
        countdown = .running(endsAt: now().addingTimeInterval(remaining))
        updateTicker()
    }

    func cancelCountdown() {
        lastSoundAt = nil
        countdownDuration = 0
        countdown = .idle
        updateTicker()
    }

    /// Clears a finished countdown and stops its repeating sound.
    func dismissFinished() {
        guard case .finished = countdown else { return }
        cancelCountdown()
    }

    func remaining(now: Date) -> TimeInterval {
        switch countdown {
        case .idle, .finished: return 0
        case .running(let endsAt): return max(0, endsAt.timeIntervalSince(now))
        case .paused(let remaining): return remaining
        }
    }

    // MARK: Stopwatch

    /// Starts from zero, or resumes when paused.
    func startStopwatch() {
        switch stopwatch {
        case .idle: stopwatch = .running(startedAt: now(), accumulated: 0)
        case .paused(let elapsed): stopwatch = .running(startedAt: now(), accumulated: elapsed)
        case .running: return
        }
        updateTicker()
    }

    func pauseStopwatch() {
        guard case .running = stopwatch else { return }
        stopwatch = .paused(elapsed: stopwatchElapsed(now: now()))
        updateTicker()
    }

    func resetStopwatch() {
        stopwatch = .idle
        updateTicker()
    }

    func stopwatchElapsed(now: Date) -> TimeInterval {
        switch stopwatch {
        case .idle: return 0
        case .running(let startedAt, let accumulated): return accumulated + max(0, now.timeIntervalSince(startedAt))
        case .paused(let elapsed): return elapsed
        }
    }

    // MARK: Time

    func tick(now: Date) {
        tickDate = now
        switch countdown {
        case .running(let endsAt) where now >= endsAt:
            countdown = .finished(at: now)
            lastSoundAt = now
            playSound()
            transientSubject.send(IslandTransient(id: "timerDone", kind: .timer, payload: .timerDone,
                                                  duration: Self.transientDuration, sticky: false))
        case .finished(let finishedAt):
            if let last = lastSoundAt,
               now.timeIntervalSince(last) >= Self.soundInterval,
               now.timeIntervalSince(finishedAt) < Self.soundDuration {
                lastSoundAt = now
                playSound()
            }
        default:
            break
        }
        updateTicker()
    }

    private var needsTicker: Bool {
        if case .running = stopwatch { return true }
        switch countdown {
        case .running: return true
        case .finished(let finishedAt): return tickDate.timeIntervalSince(finishedAt) < Self.soundDuration
        case .idle, .paused: return false
        }
    }

    private func updateTicker() {
        guard startsTicker else { return }
        if needsTicker {
            guard ticker == nil else { return }
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick(now: self?.now() ?? Date()) }
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        } else {
            ticker?.invalidate()
            ticker = nil
        }
    }
}
