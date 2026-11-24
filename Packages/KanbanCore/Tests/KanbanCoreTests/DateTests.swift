import Foundation
import Testing
@testable import KanbanCore

@Suite("Date-only values")
struct CalendarDayTests {
    @Test func isoRoundTrip() throws {
        let day = CalendarDay(year: 2026, month: 10, day: 12)
        #expect(day.isoString == "2026-10-12")
        #expect(CalendarDay(isoString: "2026-10-12") == day)
        #expect(CalendarDay(isoString: "2026-02-31") == nil)
        #expect(CalendarDay(isoString: "someday") == nil)
        let data = try JSONEncoder().encode([day])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-10-12\"]")
    }

    @Test func dayIsTakenInTheUsersTimeZone() {
        // 00:30 IST on 12 Oct is still 11 Oct in UTC.
        let instant = Fixtures.istCalendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 0, minute: 30))!
        #expect(CalendarDay(instant, calendar: Fixtures.istCalendar) == CalendarDay(year: 2026, month: 10, day: 12))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        #expect(CalendarDay(instant, calendar: utc) == CalendarDay(year: 2026, month: 10, day: 11))
    }

    @Test func dueDateSurvivesTimeZoneChange() throws {
        // Saved in IST, read back after switching to New York: same calendar day.
        var card = Fixtures.card("Due Wed", .todo, 1)
        card.dueDate = CalendarDay(year: 2026, month: 10, day: 14)
        let data = try BoardCoding.encode(BoardFile(cards: [card]))
        guard case .board(let file) = BoardCoding.decode(data) else { Issue.record("decode failed"); return }
        #expect(file.cards.first?.dueDate == CalendarDay(year: 2026, month: 10, day: 14))
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let localMidnight = file.cards[0].dueDate!.date(in: newYork)
        #expect(CalendarDay(localMidnight, calendar: newYork) == CalendarDay(year: 2026, month: 10, day: 14))
    }

    @Test func arithmeticAcrossDST() {
        // US DST ends 1 Nov 2026; day maths must not gain or lose a day.
        let before = CalendarDay(year: 2026, month: 10, day: 31)
        #expect(before.adding(days: 1) == CalendarDay(year: 2026, month: 11, day: 1))
        #expect(before.adding(days: 2) == CalendarDay(year: 2026, month: 11, day: 2))
        #expect(before.days(until: CalendarDay(year: 2026, month: 11, day: 7)) == 7)
        #expect(CalendarDay(year: 2026, month: 12, day: 31).adding(days: 1) == CalendarDay(year: 2027, month: 1, day: 1))
    }

    @Test func weekday() {
        #expect(Fixtures.saturday.weekday == 7)
        #expect(CalendarDay(year: 2026, month: 10, day: 12).weekday == 2) // the seed's "Mon 12 Oct"
    }
}

@Suite("Date labels")
struct DateLabelTests {
    let today = Fixtures.saturday
    let locale = Locale(identifier: "en_IN")

    @Test func dueLabels() {
        #expect(DateLabels.due(today, today: today, locale: locale).text == "Today")
        #expect(DateLabels.due(today.adding(days: 1), today: today, locale: locale).text == "Tomorrow")
        #expect(DateLabels.due(today.adding(days: 6), today: today, locale: locale).text == "Fri")
        #expect(DateLabels.due(CalendarDay(year: 2026, month: 10, day: 24), today: today, locale: locale).text == "24 Oct")
        #expect(DateLabels.due(CalendarDay(year: 2027, month: 1, day: 5), today: today, locale: locale).text == "5 Jan 2027")
        let yesterday = DateLabels.due(today.adding(days: -1), today: today, locale: locale)
        #expect(yesterday.text == "Overdue · 1d")
        #expect(yesterday.isOverdue)
        #expect(DateLabels.due(today.adding(days: -2), today: today, locale: locale).text == "Overdue · 2d")
    }

    @Test func labelChangesAfterMidnight() {
        let due = today
        #expect(DateLabels.due(due, today: today, locale: locale).text == "Today")
        #expect(DateLabels.due(due, today: today.adding(days: 1), locale: locale).text == "Overdue · 1d")
    }

    @Test func startLabels() {
        #expect(DateLabels.starts(CalendarDay(year: 2026, month: 10, day: 12), today: today, locale: locale)?.text == "Starts Mon")
        #expect(DateLabels.starts(today.adding(days: 1), today: today, locale: locale)?.text == "Starts tomorrow")
        #expect(DateLabels.starts(today, today: today, locale: locale) == nil)
        #expect(DateLabels.starts(today.adding(days: -3), today: today, locale: locale) == nil)
    }

    @Test func doneCardsShowNoDateLabels() {
        var card = Fixtures.card("x", .done, 1)
        card.dueDate = today.adding(days: -3)
        #expect(DateLabels.labels(for: card, today: today, locale: locale).isEmpty)
    }

    @Test func seedRecruiterCardShowsStartsMon() {
        let file = Seed.file(now: Fixtures.saturdayEvening)
        let recruiter = file.cards.first { $0.title.hasPrefix("Recruiter") }!
        #expect(DateLabels.labels(for: recruiter, today: today, locale: locale).map(\.text) == ["Starts Mon"])
    }
}

@Suite("Quick syntax")
struct QuickSyntaxTests {
    let today = Fixtures.saturday // Saturday 10 Oct 2026

    @Test func priorityCategoryAndDue() {
        let result = QuickSyntax.parse("Email placement office !high #Brochure due:fri", today: today)
        #expect(result.title == "Email placement office")
        #expect(result.priority == .high)
        #expect(result.category == "Brochure")
        #expect(result.dueDate == CalendarDay(year: 2026, month: 10, day: 16))
    }

    @Test func dueVariants() {
        func due(_ text: String) -> CalendarDay? { QuickSyntax.parse("Task \(text)", today: today).dueDate }
        #expect(due("due:tomorrow") == CalendarDay(year: 2026, month: 10, day: 11))
        #expect(due("due:today") == today)
        #expect(due("due:sat") == today) // the coming Saturday is today
        #expect(due("due:mon") == CalendarDay(year: 2026, month: 10, day: 12))
        #expect(due("due:14 oct") == CalendarDay(year: 2026, month: 10, day: 14))
        #expect(due("due:14oct") == CalendarDay(year: 2026, month: 10, day: 14))
        #expect(due("due:oct 14") == CalendarDay(year: 2026, month: 10, day: 14))
        #expect(due("due:5 jan") == CalendarDay(year: 2027, month: 1, day: 5)) // next occurrence
        #expect(due("due:14/10") == CalendarDay(year: 2026, month: 10, day: 14)) // day first
        #expect(due("due:2026-11-02") == CalendarDay(year: 2026, month: 11, day: 2))
        #expect(due("due:+3") == CalendarDay(year: 2026, month: 10, day: 13))
        #expect(due("due: fri") == CalendarDay(year: 2026, month: 10, day: 16))
    }

    @Test func multiWordDateIsRemovedFromTitle() {
        let result = QuickSyntax.parse("Send deck due:14 oct to Priya", today: today)
        #expect(result.title == "Send deck to Priya")
        #expect(result.dueDate == CalendarDay(year: 2026, month: 10, day: 14))
    }

    @Test func unparseableTextIsKept() {
        let result = QuickSyntax.parse("Think about it due:someday", today: today)
        #expect(result.title == "Think about it due:someday")
        #expect(result.dueDate == nil)
        #expect(QuickSyntax.parse("Rank #1 on list !important", today: today).title == "Rank #1 on list !important")
    }

    @Test func titleNeverEndsUpEmpty() {
        let result = QuickSyntax.parse("!high #Brochure", today: today)
        #expect(result.title == "!high #Brochure")
        #expect(result.priority == nil)
    }

    @Test func categoryReusesExistingSpelling() {
        let result = QuickSyntax.parse("Call HRs #recruiter-outreach", today: today, existingCategories: ["Recruiter outreach"])
        #expect(result.category == "Recruiter outreach")
        #expect(QuickSyntax.parse("x #Mock_interviews", today: today).category == "Mock interviews")
    }

    @Test func plainTitlesAreUntouched() {
        let raw = "Post infographic on LinkedIn  — emoji 🎯 and हिंदी"
        #expect(QuickSyntax.parse(raw, today: today).title == raw)
    }
}
