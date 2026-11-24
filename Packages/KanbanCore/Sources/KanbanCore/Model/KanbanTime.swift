import Foundation

/// Timestamps are kept to whole milliseconds, which is exactly what the file
/// stores. That way a board in memory and the same board read back from disk
/// compare equal, and the merge never sees phantom "changes".
public enum KanbanTime {
    public static func now() -> Date { round(Date()) }

    public static func round(_ date: Date) -> Date {
        fromMilliseconds((date.timeIntervalSince1970 * 1000).rounded())
    }

    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// The single conversion used both when rounding and when decoding, so the
    /// two always produce bit-identical `Date`s.
    static func fromMilliseconds(_ milliseconds: Double) -> Date {
        Date(timeIntervalSince1970: milliseconds / 1000)
    }
}
