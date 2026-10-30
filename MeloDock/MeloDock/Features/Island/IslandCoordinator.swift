import Combine
import Foundation

/// Owns island state: merged activity selection, expansion, and hover behavior.
/// Schedules `fire` after `delay` seconds; cancelling the result stops it. Injected so tests can drive time.
typealias TransientScheduler = (_ delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> AnyCancellable

@MainActor
final class IslandCoordinator: ObservableObject {
    @Published private(set) var selection = IslandSelection(primary: nil, secondary: nil)
    @Published private(set) var isExpanded = false
    @Published var isIslandEnabled: Bool {
        didSet { if !isIslandEnabled { clearTransients() } }
    }
    /// Kinds the user has enabled; activities and transients of other kinds are ignored.
    @Published var enabledKinds: Set<IslandActivity.Kind> = IslandKindFilter.all {
        didSet { if enabledKinds != oldValue { applyEnabledKinds(removed: oldValue.subtracting(enabledKinds)) } }
    }
    @Published private(set) var transient: IslandTransient?
    @Published private(set) var notch: NotchGeometry?

    var onExpandedChanged: ((Bool) -> Void)?

    var mode: IslandMode {
        Self.mode(isExpanded: isExpanded, enabled: isIslandEnabled,
                  hasPrimary: selection.primary != nil, hasTransient: transient != nil)
    }

    static func mode(isExpanded: Bool, enabled: Bool, hasPrimary: Bool, hasTransient: Bool) -> IslandMode {
        if isExpanded { return .expanded }
        if enabled && hasTransient { return .transient }
        if enabled && hasPrimary { return .compact }
        return .idle
    }

    static let defaultScheduler: TransientScheduler = { delay, fire in
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { fire() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return AnyCancellable { timer.invalidate() }
    }

    private let hoverDelay: TimeInterval
    private var latest: [Int: [IslandActivity]] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var pendingHover: DispatchWorkItem?
    private var pointerInside = false
    private let now: () -> Date
    private let scheduler: TransientScheduler
    private var queue = TransientQueue()
    private var expiryTimer: AnyCancellable?

    init(sources: [ActivitySource], isIslandEnabled: Bool = true, hoverDelay: TimeInterval = 0.3,
         now: @escaping () -> Date = Date.init,
         scheduler: @escaping TransientScheduler = IslandCoordinator.defaultScheduler) {
        self.isIslandEnabled = isIslandEnabled
        self.hoverDelay = hoverDelay
        self.now = now
        self.scheduler = scheduler
        for (index, source) in sources.enumerated() {
            source.activitiesPublisher
                .sink { [weak self] list in
                    guard let self else { return }
                    self.latest[index] = list
                    self.recomputeSelection()
                }
                .store(in: &cancellables)
            source.transientsPublisher
                .sink { [weak self] item in self?.receive(item) }
                .store(in: &cancellables)
        }
    }

    private func recomputeSelection() {
        let enabled = latest.values.flatMap { $0 }.filter { enabledKinds.contains($0.kind) }
        selection = IslandSelection.select(from: enabled)
    }

    private func applyEnabledKinds(removed: Set<IslandActivity.Kind>) {
        recomputeSelection()
        for kind in removed { queue.remove(kind: kind, now: now()) }
        syncTransient()
    }

    func updateNotch(_ notch: NotchGeometry?) {
        self.notch = notch
    }

    func toggleExpanded() {
        cancelHover()
        setExpanded(!isExpanded)
    }

    /// Expands without toggling, so a click racing the hover delay cannot collapse the island.
    func expand() {
        cancelHover()
        setExpanded(true)
    }

    func pointerEntered() {
        pointerInside = true
        guard mode == .compact else { return }
        cancelHover()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHover = nil
            if self.pointerInside && self.mode == .compact { self.setExpanded(true) }
        }
        pendingHover = item
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverDelay, execute: item)
    }

    func pointerExited() {
        let wasInside = pointerInside
        pointerInside = false
        cancelHover()
        if isExpanded && wasInside { setExpanded(false) }
    }

    private func cancelHover() {
        pendingHover?.cancel()
        pendingHover = nil
    }

    /// Transients appear only while collapsed and enabled; anything else is dropped, not deferred.
    private func receive(_ item: IslandTransient) {
        guard isIslandEnabled, !isExpanded, enabledKinds.contains(item.kind) else { return }
        queue.enqueue(item, now: now())
        syncTransient()
    }

    private func expireTransient() {
        _ = queue.tick(now: now())
        syncTransient()
    }

    private func clearTransients() {
        queue.clear()
        syncTransient()
    }

    private func syncTransient() {
        if transient != queue.current { transient = queue.current }
        expiryTimer?.cancel()
        expiryTimer = nil
        guard let expiresAt = queue.expiresAt else { return }
        expiryTimer = scheduler(max(0, expiresAt.timeIntervalSince(now()))) { [weak self] in
            self?.expireTransient()
        }
    }

    private func setExpanded(_ value: Bool) {
        guard value != isExpanded else { return }
        isExpanded = value
        if value { clearTransients() }
        onExpandedChanged?(value)
    }
}

extension SettingsStore {
    /// Kinds the island should show, re-evaluated whenever a per-activity switch changes.
    var enabledKindsPublisher: AnyPublisher<Set<IslandActivity.Kind>, Never> {
        Publishers.CombineLatest3($showPower, $showAudio, $showCapture)
            .map { IslandKindFilter.enabledKinds(showPower: $0, showAudio: $1, showCapture: $2) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
