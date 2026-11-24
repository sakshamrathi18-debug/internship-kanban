import Foundation

/// Optional shorthand typed into a new card's title:
/// `!high` `!med` `!low`, `#Brochure`, `due:fri` / `due:14 oct` / `due:tomorrow`.
/// Recognised tokens are removed from the title; anything that doesn't parse
/// (e.g. `due:someday`) stays in the title exactly as typed.
public struct QuickSyntaxResult: Equatable, Sendable {
    public var title: String
    public var priority: Priority?
    public var category: String?
    public var dueDate: CalendarDay?

    public var hasExtras: Bool { priority != nil || category != nil || dueDate != nil }
}

public enum QuickSyntax {
    public static func parse(_ raw: String, today: CalendarDay, existingCategories: [String] = []) -> QuickSyntaxResult {
        let tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        var kept: [String] = []
        var result = QuickSyntaxResult(title: "")
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            let lower = token.lowercased()

            if result.priority == nil, lower.hasPrefix("!"), let priority = priority(from: String(lower.dropFirst())) {
                result.priority = priority
                i += 1
                continue
            }

            if result.category == nil, token.hasPrefix("#"), token.count > 1,
               token.dropFirst().first?.isLetter == true {
                result.category = category(from: String(token.dropFirst()), existing: existingCategories)
                i += 1
                continue
            }

            if result.dueDate == nil, lower.hasPrefix("due:") {
                var value = String(lower.dropFirst(4))
                var consumed = 1
                if value.isEmpty, i + 1 < tokens.count { // "due: fri"
                    value = tokens[i + 1].lowercased()
                    consumed = 2
                }
                // Up to two more tokens for "14 oct" / "14 oct 2026" / "oct 14".
                let following = tokens.dropFirst(i + consumed).prefix(2).map { $0.lowercased() }
                if let (day, extra) = parseDate(value, following: following, today: today) {
                    result.dueDate = day
                    i += consumed + extra
                    continue
                }
            }

            kept.append(token)
            i += 1
        }

        let stripped = kept.joined(separator: " ")
        if !result.hasExtras || stripped.trimmingCharacters(in: .whitespaces).isEmpty {
            // Nothing recognised, or the title would be empty: keep the words as typed.
            return QuickSyntaxResult(title: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        result.title = stripped
        return result
    }

    // MARK: - Pieces

    static func priority(from word: String) -> Priority? {
        switch word {
        case "high", "hi", "h": .high
        case "med", "medium", "m": .medium
        case "low", "lo", "l": .low
        default: nil
        }
    }

    /// Reuses an existing category's spelling when it matches loosely,
    /// so `#recruiter-outreach` files under "Recruiter outreach".
    static func category(from word: String, existing: [String]) -> String {
        func normalised(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let key = normalised(word)
        if let match = existing.first(where: { normalised($0) == key }) { return match }
        return word.replacingOccurrences(of: "_", with: " ")
    }

    private static let weekdays: [String: Int] = [
        "sun": 1, "sunday": 1,
        "mon": 2, "monday": 2,
        "tue": 3, "tues": 3, "tuesday": 3,
        "wed": 4, "weds": 4, "wednesday": 4,
        "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6,
        "sat": 7, "saturday": 7,
    ]

    private static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
        "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7,
        "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10, "nov": 11, "november": 11, "dec": 12, "december": 12,
    ]

    /// Parses the value after `due:`. Returns the day and how many of the
    /// `following` tokens it used.
    static func parseDate(_ value: String, following: [String], today: CalendarDay) -> (CalendarDay, Int)? {
        let v = value.trimmingCharacters(in: CharacterSet(charactersIn: ",."))
        switch v {
        case "today", "tod": return (today, 0)
        case "tomorrow", "tmr", "tmrw", "tom": return (today.adding(days: 1), 0)
        case "nextweek", "next-week": return (nextWeekday(2, after: today, includeToday: false), 0)
        default: break
        }

        // Weekday: the coming one, today included.
        if let weekday = weekdays[v] {
            return (nextWeekday(weekday, after: today, includeToday: true), 0)
        }

        // +3 or 3d: that many days from today.
        if let n = relativeDays(v) { return (today.adding(days: n), 0) }

        // 2026-10-14
        if v.count == 10, let day = CalendarDay(isoString: v) { return (day, 0) }

        // 14/10 or 14/10/2026 (day first, as in India).
        let slashParts = v.split(separator: "/").map(String.init)
        if slashParts.count >= 2, let d = Int(slashParts[0]), let m = Int(slashParts[1]) {
            let y = slashParts.count == 3 ? Int(slashParts[2]).map { $0 < 100 ? 2000 + $0 : $0 } : nil
            if let day = makeDay(day: d, month: m, year: y, today: today) { return (day, 0) }
            return nil
        }

        // 14oct, oct14, 14-oct
        if let (d, m) = dayMonthGlued(v), let day = makeDay(day: d, month: m, year: nil, today: today) {
            return (day, 0)
        }

        // "14 oct [2026]" or "oct 14 [2026]" across tokens.
        let next = following.first.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",.")) }
        let yearToken = following.count > 1 ? Int(following[1].trimmingCharacters(in: CharacterSet(charactersIn: ",."))) : nil
        let year = yearToken.flatMap { (1900...9999).contains($0) ? $0 : nil }
        if let d = Int(v), let next, let m = months[next] {
            if let day = makeDay(day: d, month: m, year: year, today: today) { return (day, year == nil ? 1 : 2) }
        }
        if let m = months[v], let next, let d = Int(next) {
            if let day = makeDay(day: d, month: m, year: year, today: today) { return (day, year == nil ? 1 : 2) }
        }
        return nil
    }

    private static func relativeDays(_ v: String) -> Int? {
        if v.hasPrefix("+"), let n = Int(v.dropFirst()), (0...3650).contains(n) { return n }
        if v.hasSuffix("d"), let n = Int(v.dropLast()), (0...3650).contains(n) { return n }
        return nil
    }

    private static func dayMonthGlued(_ v: String) -> (Int, Int)? {
        let cleaned = v.replacingOccurrences(of: "-", with: "")
        let digits = cleaned.prefix(while: \.isNumber)
        if !digits.isEmpty, let d = Int(digits), let m = months[String(cleaned.dropFirst(digits.count))] {
            return (d, m)
        }
        let letters = cleaned.prefix(while: \.isLetter)
        if !letters.isEmpty, let m = months[String(letters)], let d = Int(cleaned.dropFirst(letters.count)) {
            return (d, m)
        }
        return nil
    }

    /// With no year given, picks the next time that date comes round (today counts).
    private static func makeDay(day: Int, month: Int, year: Int?, today: CalendarDay) -> CalendarDay? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        if let year {
            return CalendarDay(isoString: String(format: "%04d-%02d-%02d", year, month, day))
        }
        for y in [today.year, today.year + 1] {
            if let candidate = CalendarDay(isoString: String(format: "%04d-%02d-%02d", y, month, day)), candidate >= today {
                return candidate
            }
        }
        return nil
    }

    private static func nextWeekday(_ weekday: Int, after today: CalendarDay, includeToday: Bool) -> CalendarDay {
        var offset = (weekday - today.weekday + 7) % 7
        if offset == 0 && !includeToday { offset = 7 }
        return today.adding(days: offset)
    }
}
