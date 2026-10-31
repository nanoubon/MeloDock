import Foundation

enum SpectrumLevels {
    /// Maps `levels` onto `count` bars: neighbouring bands are averaged when shrinking, repeated when growing.
    static func resample(_ levels: [Float], to count: Int) -> [Float] {
        guard count > 0, !levels.isEmpty else { return [] }
        if count >= levels.count {
            return (0..<count).map { levels[min($0 * levels.count / count, levels.count - 1)] }
        }
        return (0..<count).map { bar in
            let start = bar * levels.count / count
            let end = max(start + 1, (bar + 1) * levels.count / count)
            let group = levels[start..<end]
            return group.reduce(0, +) / Float(group.count)
        }
    }
}
