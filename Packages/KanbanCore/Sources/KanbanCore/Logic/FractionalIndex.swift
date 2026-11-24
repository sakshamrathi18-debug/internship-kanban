import Foundation

/// Ordering within a column uses fractional indices, so a move rewrites one card.
public enum FractionalIndex {
    /// Below this gap between neighbours the column gets renumbered 1, 2, 3…
    public static let minimumGap = 1e-6

    /// An index that sorts between `before` and `after` (either may be absent).
    public static func between(_ before: Double?, _ after: Double?) -> Double {
        switch (before, after) {
        case (nil, nil): return 1
        case (let a?, nil): return a + 1
        case (nil, let b?): return b - 1
        case (let a?, let b?): return a + (b - a) / 2
        }
    }

    /// True when `value` sits too close to a neighbour to leave room for future inserts.
    public static func isCrowded(_ value: Double, before: Double?, after: Double?) -> Bool {
        guard value.isFinite else { return true }
        if let before, value - before < minimumGap { return true }
        if let after, after - value < minimumGap { return true }
        return false
    }
}
