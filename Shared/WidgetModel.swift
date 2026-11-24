import Foundation
import KanbanCore
import WidgetKit

struct BoardEntry: TimelineEntry, Sendable {
    enum Content: Sendable {
        /// The app has never written a board.
        case noData
        case board(Board)
    }

    let date: Date
    let content: Content

    /// Labels ("Today", "Overdue · 1d") are computed against the entry's own date,
    /// so the midnight entry relabels without the app running.
    var today: CalendarDay { CalendarDay(date) }
}

/// Reads the shared board, falling back to the last good snapshot so the
/// widget is never blank, even if the file is briefly unreadable.
enum WidgetData {
    private static var snapshotURL: URL {
        AppGroup.dataDirectory().appendingPathComponent("widget-last-good.json")
    }

    static func load() -> BoardEntry.Content {
        let persistence = FileBoardPersistence()
        switch persistence.readNow() {
        case .board(let file):
            saveSnapshot(file)
            return .board(Board(file: file))
        case .newerSchema(_, let file?):
            return .board(Board(file: file))
        case .missing:
            // Never launched → invite the user in. Deleted while the app runs →
            // the app rewrites it shortly; show what we had.
            if let snapshot = loadSnapshot() { return .board(Board(file: snapshot)) }
            return .noData
        case .unreadable, .newerSchema(_, nil):
            if let snapshot = loadSnapshot() ?? persistence.newestBackup() { return .board(Board(file: snapshot)) }
            return .noData
        }
    }

    private static func saveSnapshot(_ file: BoardFile) {
        guard let data = try? BoardCoding.encode(file) else { return }
        try? data.write(to: snapshotURL, options: .atomic)
    }

    private static func loadSnapshot() -> BoardFile? {
        guard let data = try? Data(contentsOf: snapshotURL), case .board(let file) = BoardCoding.decode(data) else { return nil }
        return file
    }

    /// The seed board, for the gallery and placeholders.
    static let sample: Board = {
        var board = Board(file: Seed.file(now: Date(timeIntervalSinceReferenceDate: 813_000_000)))
        let now = Date(timeIntervalSinceReferenceDate: 813_000_000)
        board.add(title: "Mock interview with seniors", column: .todo, now: now) { $0.priority = .low }
        board.add(title: "Alumni list from placement office", column: .onHold, now: now) {
            $0.waitingOn = "Placement office"
        }
        board.add(title: "Shortlist target companies", column: .done, now: now)
        return board
    }()
}
