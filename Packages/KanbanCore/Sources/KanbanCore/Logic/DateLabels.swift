import Foundation

public struct DateLabel: Equatable, Sendable {
    public enum Kind: Sendable { case due, starts }

    public var kind: Kind
    public var text: String
    public var isOverdue: Bool
    /// Words for VoiceOver, e.g. "due Friday" or "overdue by 2 days".
    public var spoken: String
}

/// "Today", "Tomorrow", "Fri", "14 Oct", "Overdue · 2d", "Starts Mon".
public enum DateLabels {
    public static func due(_ due: CalendarDay, today: CalendarDay, locale: Locale = .current) -> DateLabel {
        let delta = today.days(until: due)
        if delta < 0 {
            let days = -delta
            return DateLabel(kind: .due, text: "Overdue · \(days)d", isOverdue: true,
                             spoken: "overdue by \(days) \(days == 1 ? "day" : "days")")
        }
        let text = relative(due, today: today, locale: locale)
        return DateLabel(kind: .due, text: text, isOverdue: false, spoken: "due \(spokenRelative(due, today: today, locale: locale))")
    }

    /// Only for a start date that hasn't arrived yet.
    public static func starts(_ start: CalendarDay, today: CalendarDay, locale: Locale = .current) -> DateLabel? {
        guard start > today else { return nil }
        let text = today.days(until: start) == 1 ? "Starts tomorrow" : "Starts \(relative(start, today: today, locale: locale))"
        return DateLabel(kind: .starts, text: text, isOverdue: false, spoken: "starts \(spokenRelative(start, today: today, locale: locale))")
    }

    /// The labels a card's footer shows. Done cards show none: an old due date
    /// on a finished task isn't news.
    public static func labels(for card: TaskCard, today: CalendarDay, locale: Locale = .current) -> [DateLabel] {
        guard !card.isDone else { return [] }
        var result: [DateLabel] = []
        if let start = card.startDate, let label = starts(start, today: today, locale: locale) { result.append(label) }
        if let dueDay = card.dueDate { result.append(due(dueDay, today: today, locale: locale)) }
        return result
    }

    /// "Today", "Tomorrow", "Fri" (within a week), "14 Oct", or "14 Oct 2027".
    public static func relative(_ day: CalendarDay, today: CalendarDay, locale: Locale = .current) -> String {
        let delta = today.days(until: day)
        switch delta {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6: return symbols(locale).weekdays[day.weekday - 1]
        default: return short(day, today: today, locale: locale)
        }
    }

    /// "14 Oct", adding the year when it isn't this year.
    public static func short(_ day: CalendarDay, today: CalendarDay, locale: Locale = .current) -> String {
        let month = symbols(locale).months[day.month - 1]
        return day.year == today.year ? "\(day.day) \(month)" : "\(day.day) \(month) \(day.year)"
    }

    private static func spokenRelative(_ day: CalendarDay, today: CalendarDay, locale: Locale) -> String {
        let delta = today.days(until: day)
        switch delta {
        case 0: return "today"
        case 1: return "tomorrow"
        case 2...6: return symbols(locale).fullWeekdays[day.weekday - 1]
        default:
            let month = symbols(locale).fullMonths[day.month - 1]
            return day.year == today.year ? "\(day.day) \(month)" : "\(day.day) \(month) \(day.year)"
        }
    }

    private struct Symbols {
        var weekdays: [String], fullWeekdays: [String], months: [String], fullMonths: [String]
    }

    private static func symbols(_ locale: Locale) -> Symbols {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return Symbols(weekdays: calendar.shortWeekdaySymbols, fullWeekdays: calendar.weekdaySymbols,
                       months: calendar.shortMonthSymbols, fullMonths: calendar.monthSymbols)
    }
}
