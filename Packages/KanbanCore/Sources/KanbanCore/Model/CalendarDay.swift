import Foundation

/// A date with no time and no time zone: "12 Oct 2026" means the same day
/// wherever and whenever it is read. Stored in JSON as `"2026-10-12"`.
///
/// `Date` is an instant, so a due date saved at IST midnight would show as the
/// previous day after a switch to UTC. Keeping year/month/day avoids that.
public struct CalendarDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `calendar`'s time zone (the user's, by default).
    public init(_ date: Date, calendar: Calendar = .current) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    public static func today(now: Date = Date(), calendar: Calendar = .current) -> CalendarDay {
        CalendarDay(now, calendar: calendar)
    }

    /// Local midnight of this day, for date pickers and formatters.
    public func date(in calendar: Calendar = .current) -> Date {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = DateComponents(year: year, month: month, day: day, hour: 0)
        return gregorian.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    public func adding(days: Int) -> CalendarDay {
        let shifted = Self.utc.date(byAdding: .day, value: days, to: utcDate) ?? utcDate
        return CalendarDay(shifted, calendar: Self.utc)
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    public func days(until other: CalendarDay) -> Int {
        Self.utc.dateComponents([.day], from: utcDate, to: other.utcDate).day ?? 0
    }

    /// 1 = Sunday … 7 = Saturday.
    public var weekday: Int {
        Self.utc.component(.weekday, from: utcDate)
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { isoString }

    public init?(isoString: String) {
        // Accept "2026-10-12" and anything that starts with it (e.g. a full ISO timestamp).
        let head = isoString.prefix(10)
        let parts = head.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        let candidate = CalendarDay(year: y, month: m, day: d)
        // Reject impossible dates like 31 Feb by round-tripping.
        guard CalendarDay(candidate.utcDate, calendar: Self.utc) == candidate else { return nil }
        self = candidate
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // Day arithmetic happens in a fixed UTC Gregorian calendar, so DST and
    // time-zone changes can never add or lose a day.
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private var utcDate: Date {
        Self.utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date(timeIntervalSince1970: 0)
    }
}

extension CalendarDay: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let day = CalendarDay(isoString: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a yyyy-MM-dd date: \(string)")
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}
