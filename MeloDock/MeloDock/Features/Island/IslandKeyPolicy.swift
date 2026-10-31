import Foundation

/// When the island panel may take keyboard focus. Being able to become key is what lets the timer's custom
/// minutes field accept typing; everywhere else the panel stays a pure overlay.
enum IslandKeyPolicy {
    static func canBecomeKey(isExpanded: Bool, page: IslandActivity.Kind) -> Bool {
        isExpanded && page == .timer
    }
}
