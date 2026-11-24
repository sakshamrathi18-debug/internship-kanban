import Foundation
@testable import KanbanCore

/// A clock the tests can move.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    var now: Date { lock.withLock { current } }

    func advance(seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }

    func set(_ date: Date) {
        lock.withLock { current = date }
    }

    var function: @Sendable () -> Date { { [self] in self.now } }
}

enum Fixtures {
    static let ist = TimeZone(identifier: "Asia/Kolkata")!

    static var istCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ist
        calendar.locale = Locale(identifier: "en_IN")
        return calendar
    }

    /// Saturday 10 Oct 2026, 9:00 PM IST.
    static let saturdayEvening: Date = {
        istCalendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 21))!
    }()

    static let saturday = CalendarDay(year: 2026, month: 10, day: 10)

    static func tempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KanbanCoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func card(_ title: String, _ column: Column, _ index: Double, at date: Date = saturdayEvening) -> TaskCard {
        TaskCard(title: title, column: column, sortIndex: index, createdAt: date)
    }
}

extension Board {
    func titles(_ column: Column) -> [String] { cards(in: column).map(\.title) }
}
