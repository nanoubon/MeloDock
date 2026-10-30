import Combine
import Foundation

/// Owns island state: merged activity selection, expansion, and hover behavior.
@MainActor
final class IslandCoordinator: ObservableObject {
    @Published private(set) var selection = IslandSelection(primary: nil, secondary: nil)
    @Published private(set) var isExpanded = false
    @Published var isIslandEnabled: Bool
    @Published private(set) var notch: NotchGeometry?

    var onExpandedChanged: ((Bool) -> Void)?

    var mode: IslandMode {
        if isExpanded { return .expanded }
        if isIslandEnabled && selection.primary != nil { return .compact }
        return .idle
    }

    private let hoverDelay: TimeInterval
    private var latest: [Int: [IslandActivity]] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var pendingHover: DispatchWorkItem?
    private var pointerInside = false

    init(sources: [ActivitySource], isIslandEnabled: Bool = true, hoverDelay: TimeInterval = 0.3) {
        self.isIslandEnabled = isIslandEnabled
        self.hoverDelay = hoverDelay
        for (index, source) in sources.enumerated() {
            source.activitiesPublisher
                .sink { [weak self] list in
                    guard let self else { return }
                    self.latest[index] = list
                    self.selection = IslandSelection.select(from: self.latest.values.flatMap { $0 })
                }
                .store(in: &cancellables)
        }
    }

    func updateNotch(_ notch: NotchGeometry?) {
        self.notch = notch
    }

    func toggleExpanded() {
        cancelHover()
        setExpanded(!isExpanded)
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

    private func setExpanded(_ value: Bool) {
        guard value != isExpanded else { return }
        isExpanded = value
        onExpandedChanged?(value)
    }
}
