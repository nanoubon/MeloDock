import Foundation

/// FIFO of short-lived island notices, one visible at a time. Pure value type; the caller supplies the clock.
struct TransientQueue: Equatable {
    static let maxPending = 5

    private(set) var current: IslandTransient?
    private(set) var pending: [IslandTransient] = []
    /// When `current` stops being shown, or nil when nothing is showing.
    private(set) var expiresAt: Date?

    /// Same-id items coalesce: a newer one replaces the current (restarting its clock) or the pending one in place.
    mutating func enqueue(_ item: IslandTransient, now: Date) {
        if current?.id == item.id {
            show(item, now: now)
        } else if let index = pending.firstIndex(where: { $0.id == item.id }) {
            pending[index] = item
        } else if current == nil {
            show(item, now: now)
        } else {
            pending.append(item)
            if pending.count > Self.maxPending { pending.removeFirst(pending.count - Self.maxPending) }
        }
    }

    /// Advances past an expired current item. Returns true when `current` changed.
    mutating func tick(now: Date) -> Bool {
        guard current != nil, let expiresAt, now >= expiresAt else { return false }
        if pending.isEmpty {
            current = nil
            self.expiresAt = nil
        } else {
            show(pending.removeFirst(), now: now)
        }
        return true
    }

    /// Restarts the clock of the current item if it is `id` and sticky (e.g. a drag that keeps producing events).
    mutating func touch(id: String, now: Date) {
        guard let current, current.id == id, current.sticky else { return }
        expiresAt = now.addingTimeInterval(current.duration)
    }

    mutating func clear() {
        current = nil
        pending.removeAll()
        expiresAt = nil
    }

    private mutating func show(_ item: IslandTransient, now: Date) {
        current = item
        expiresAt = now.addingTimeInterval(item.duration)
    }
}
