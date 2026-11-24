import Foundation

/// The numbers in the summary strip and the small widget.
public struct BoardStats: Equatable, Sendable {
    public var total: Int
    public var todo: Int
    public var inProgress: Int
    public var onHold: Int
    public var done: Int
    public var doneThisWeek: Int

    /// Done ÷ total of the cards on the board (archived cards excluded), 0…1.
    public var fractionComplete: Double { total == 0 ? 0 : Double(done) / Double(total) }

    public func count(for column: Column) -> Int {
        switch column {
        case .todo: todo
        case .inProgress: inProgress
        case .onHold: onHold
        case .done: done
        }
    }

    public init(cards: [TaskCard], now: Date = Date(), calendar: Calendar = .current) {
        let active = cards.filter { !$0.isArchived }
        total = active.count
        todo = active.filter { $0.column == .todo }.count
        inProgress = active.filter { $0.column == .inProgress }.count
        onHold = active.filter { $0.column == .onHold }.count
        done = active.filter { $0.column == .done }.count
        // Archived cards still count: they were finished this week even if the
        // archive window is shorter than a week.
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        doneThisWeek = cards.filter { card in
            guard card.column == .done, let completed = card.completedAt, let week else { return false }
            return week.contains(completed)
        }.count
    }

    /// Whether In Progress is over the soft WIP limit.
    public static func isOverWIP(inProgress: Int, limit: Int?) -> Bool {
        guard let limit else { return false }
        return inProgress > limit
    }
}
