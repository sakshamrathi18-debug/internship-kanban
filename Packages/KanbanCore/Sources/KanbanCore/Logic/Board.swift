import Foundation

/// What one operation did to each card it touched. `nil` means "didn't exist".
/// Used for undo/redo and so the UI knows which cards just moved or arrived.
public struct CardChange: Equatable, Sendable {
    public var before: TaskCard?
    public var after: TaskCard?
}

public struct CardDiff: Equatable, Sendable {
    public var changes: [UUID: CardChange] = [:]

    public init(changes: [UUID: CardChange] = [:]) {
        self.changes = changes
    }

    public var isEmpty: Bool { changes.isEmpty }

    /// Folds a later diff into this one: earliest `before`, latest `after`.
    public mutating func append(_ later: CardDiff) {
        for (id, change) in later.changes {
            if let existing = changes[id] {
                changes[id] = CardChange(before: existing.before, after: change.after)
            } else {
                changes[id] = change
            }
        }
        // Drop cards that ended up where they started (e.g. typed then reverted).
        changes = changes.filter { _, change in
            switch (change.before, change.after) {
            case (nil, nil): false
            case let (before?, after?): !before.hasSameContent(as: after)
            default: true
            }
        }
    }

    public var inverted: CardDiff {
        CardDiff(changes: changes.mapValues { CardChange(before: $0.after, after: $0.before) })
    }
}

/// The board as plain data plus every rule that changes it. The app's store
/// and the widget's "→" intent both mutate a `Board`, so the rules live in one place.
public struct Board: Equatable, Sendable {
    public private(set) var cardsByID: [UUID: TaskCard]
    public var settings: BoardSettings

    public init(cards: [TaskCard] = [], settings: BoardSettings = BoardSettings()) {
        cardsByID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b })
        self.settings = settings
    }

    public init(file: BoardFile) {
        self.init(cards: file.cards, settings: file.settings)
    }

    /// Stable order on disk (column, then position) keeps the JSON readable.
    public var file: BoardFile {
        let order = Dictionary(uniqueKeysWithValues: Column.allCases.enumerated().map { ($1, $0) })
        let sorted = cardsByID.values.sorted { a, b in
            if a.isArchived != b.isArchived { return !a.isArchived }
            if a.column != b.column { return order[a.column]! < order[b.column]! }
            return Board.precedes(a, b)
        }
        return BoardFile(cards: sorted, settings: settings)
    }

    public subscript(id: UUID) -> TaskCard? { cardsByID[id] }

    public var isEmpty: Bool { cardsByID.isEmpty }

    /// Active (not archived) cards in a column, top to bottom: grouped by
    /// priority (High → Medium → Low → None), then by position in the group.
    /// Done is one group, ordered by position only.
    public func cards(in column: Column) -> [TaskCard] {
        cardsByID.values.filter { $0.column == column && !$0.isArchived }.sorted(by: Board.precedes)
    }

    /// The cards sharing a priority group with a card of `priority` in `column`.
    public func group(_ priority: Priority, in column: Column) -> [TaskCard] {
        cards(in: column).filter { column == .done || $0.priority == priority }
    }

    /// The priority groups of a column in display order, non-empty only.
    public func groups(in column: Column) -> [(priority: Priority, cards: [TaskCard])] {
        if column == .done {
            let cards = cards(in: .done)
            return cards.isEmpty ? [] : [(.none, cards)]
        }
        return Priority.boardOrder.compactMap { priority in
            let cards = group(priority, in: column)
            return cards.isEmpty ? nil : (priority, cards)
        }
    }

    public var activeCards: [TaskCard] { cardsByID.values.filter { !$0.isArchived } }

    /// Archived cards, most recently completed first.
    public var archivedCards: [TaskCard] {
        cardsByID.values.filter(\.isArchived).sorted {
            ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt)
        }
    }

    /// Distinct categories, alphabetical. Spellings that differ only in case
    /// collapse to the one used first.
    public var categories: [String] {
        var firstUse: [String: (spelling: String, created: Date)] = [:]
        for card in cardsByID.values where !card.category.isEmpty {
            let key = card.category.lowercased()
            if let existing = firstUse[key], (existing.created, existing.spelling) <= (card.createdAt, card.category) { continue }
            firstUse[key] = (card.category, card.createdAt)
        }
        return firstUse.values.map(\.spelling).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func precedes(_ a: TaskCard, _ b: TaskCard) -> Bool {
        if a.column != .done, a.priority != b.priority { return a.priority.rank < b.priority.rank }
        if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }

    // MARK: - Adding

    public enum Position: Equatable, Sendable {
        case top, bottom
        case after(UUID)
    }

    /// Adds a card and returns it. The title must already be non-empty.
    @discardableResult
    public mutating func add(
        title: String,
        column: Column,
        position: Position = .bottom,
        now: Date,
        configure: (inout TaskCard) -> Void = { _ in }
    ) -> (card: TaskCard, diff: CardDiff) {
        var card = TaskCard(title: title, column: column, sortIndex: 0, createdAt: now)
        configure(&card)
        card.column = column
        // Positions are within the card's priority group.
        let list = group(card.priority, in: column)
        let slot: Int
        switch position {
        case .top: slot = 0
        case .bottom: slot = list.count
        case .after(let id): slot = (list.firstIndex { $0.id == id }).map { $0 + 1 } ?? list.count
        }
        card.completedAt = column == .done ? now : nil
        card.updatedAt = now
        var diff = CardDiff()
        place(&card, in: list, at: slot, diff: &diff)
        diff.changes[card.id] = CardChange(before: nil, after: cardsByID[card.id])
        return (cardsByID[card.id]!, diff)
    }

    // MARK: - Moving

    /// Moves a card to `index` within a priority group of the target column.
    /// Passing a different `priority` changes the card's priority (dropping it
    /// into another panel); nil keeps it. In Done, priority is kept and the
    /// whole column is one group. Returns nil (and changes nothing, not even
    /// `updatedAt`) when the card is already there.
    @discardableResult
    public mutating func move(_ id: UUID, to column: Column, priority newPriority: Priority? = nil, index: Int, now: Date) -> CardDiff? {
        guard var card = cardsByID[id], !card.isArchived else { return nil }
        let priority = column == .done ? card.priority : (newPriority ?? card.priority)
        let full = group(priority, in: column)
        let others = full.filter { $0.id != id }
        let slot = min(max(index, 0), others.count)
        if card.column == column, card.priority == priority, full.firstIndex(where: { $0.id == id }) == slot {
            return nil
        }
        let before = card
        card.priority = priority
        if card.column != column {
            if column == .done { card.completedAt = now }
            if card.column == .done { card.completedAt = nil }
            card.column = column
        }
        card.updatedAt = now
        var diff = CardDiff()
        place(&card, in: others, at: slot, diff: &diff)
        diff.changes[id] = CardChange(before: before, after: cardsByID[id])
        return diff
    }

    /// Next or previous column in board order, landing at the top so it stays in view.
    @discardableResult
    public mutating func moveToAdjacentColumn(_ id: UUID, forward: Bool, now: Date) -> CardDiff? {
        guard let card = cardsByID[id], let target = forward ? card.column.next : card.column.previous else { return nil }
        return move(id, to: target, index: 0, now: now)
    }

    /// One step up (−1) or down (+1) within the card's priority group; it
    /// never crosses into another priority.
    @discardableResult
    public mutating func reorder(_ id: UUID, by offset: Int, now: Date) -> CardDiff? {
        guard let card = cardsByID[id] else { return nil }
        let list = group(card.priority, in: card.column)
        guard let current = list.firstIndex(where: { $0.id == id }) else { return nil }
        let target = current + offset
        guard target >= 0, target < list.count else { return nil }
        return move(id, to: card.column, index: target, now: now)
    }

    /// The widget's "→": To Do → In Progress → Done, On Hold → In Progress.
    @discardableResult
    public mutating func widgetMoveForward(_ id: UUID, now: Date) -> CardDiff? {
        guard let card = cardsByID[id], !card.isArchived, let target = card.column.widgetForward else { return nil }
        return move(id, to: target, index: 0, now: now)
    }

    // MARK: - Editing

    /// Applies `change` to a card. Returns nil and leaves `updatedAt` alone if
    /// nothing actually changed. Column changes should go through `move`.
    @discardableResult
    public mutating func update(_ id: UUID, now: Date, _ change: (inout TaskCard) -> Void) -> CardDiff? {
        guard let before = cardsByID[id] else { return nil }
        var card = before
        change(&card)
        card.title = String(card.title.prefix(TaskCard.maxTitleLength))
        card.nextStep = String(card.nextStep.prefix(TaskCard.maxNextStepLength))
        guard !card.hasSameContent(as: before) else { return nil }
        card.updatedAt = now
        var diff = CardDiff()
        if card.priority != before.priority, !card.isArchived, card.column != .done {
            // A new priority means a new panel: land at the top of it.
            let others = group(card.priority, in: card.column).filter { $0.id != id }
            place(&card, in: others, at: 0, diff: &diff)
        } else {
            cardsByID[id] = card
        }
        diff.changes[id] = CardChange(before: before, after: cardsByID[id])
        return diff
    }

    @discardableResult
    public mutating func delete(_ id: UUID) -> CardDiff? {
        guard let card = cardsByID.removeValue(forKey: id) else { return nil }
        return CardDiff(changes: [id: CardChange(before: card, after: nil)])
    }

    /// A copy placed just below the original.
    @discardableResult
    public mutating func duplicate(_ id: UUID, now: Date) -> (card: TaskCard, diff: CardDiff)? {
        guard let original = cardsByID[id], !original.isArchived else { return nil }
        return add(title: original.title, column: original.column, position: .after(id), now: now) { copy in
            copy.nextStep = original.nextStep
            copy.waitingOn = original.waitingOn
            copy.category = original.category
            copy.priority = original.priority
            copy.startDate = original.startDate
            copy.dueDate = original.dueDate
        }
    }

    // MARK: - Archive

    /// Done cards completed more than `archiveAfterDays` calendar days before
    /// `today` get archived. Never un-archives anything, and a completion date in
    /// the future (clock set backwards) is simply not old enough.
    @discardableResult
    public mutating func archiveOldDoneCards(today: CalendarDay, calendar: Calendar = .current, now: Date) -> CardDiff? {
        var diff = CardDiff()
        for card in cards(in: .done) {
            let completed = CalendarDay(card.completedAt ?? card.updatedAt, calendar: calendar)
            guard completed.days(until: today) > settings.archiveAfterDays else { continue }
            var archived = card
            archived.isArchived = true
            archived.updatedAt = now
            cardsByID[card.id] = archived
            diff.changes[card.id] = CardChange(before: card, after: archived)
        }
        return diff.isEmpty ? nil : diff
    }

    /// "Restore to To Do": back on the board at the top of To Do.
    @discardableResult
    public mutating func restoreFromArchive(_ id: UUID, now: Date) -> CardDiff? {
        guard var card = cardsByID[id], card.isArchived else { return nil }
        let before = card
        card.isArchived = false
        card.column = .todo
        card.completedAt = nil
        card.updatedAt = now
        var diff = CardDiff()
        place(&card, in: group(card.priority, in: .todo), at: 0, diff: &diff)
        diff.changes[id] = CardChange(before: before, after: cardsByID[id])
        return diff
    }

    // MARK: - Undo support

    /// Puts cards back to the given versions (nil = remove). `updatedAt` is
    /// bumped to `now` so an undo wins the next merge against the file on disk.
    @discardableResult
    public mutating func restore(_ versions: [UUID: TaskCard?], now: Date) -> CardDiff {
        var diff = CardDiff()
        for (id, version) in versions {
            let before = cardsByID[id]
            if var card = version {
                card.updatedAt = now
                cardsByID[id] = card
            } else {
                cardsByID.removeValue(forKey: id)
            }
            diff.changes[id] = CardChange(before: before, after: cardsByID[id])
        }
        return diff
    }

    // MARK: - Merge

    /// Combines the in-memory board with what's on disk (e.g. after the widget
    /// moved a card). Per card, the newer `updatedAt` wins; on a tie, memory wins.
    /// Cards only on disk are added unless this session deleted them.
    public static func merge(memory: Board, disk: Board, deletedIDs: Set<UUID>) -> Board {
        var result = memory
        for (id, diskCard) in disk.cardsByID {
            if let mine = memory.cardsByID[id] {
                if diskCard.updatedAt > mine.updatedAt { result.cardsByID[id] = diskCard }
            } else if !deletedIDs.contains(id) {
                result.cardsByID[id] = diskCard
            }
        }
        return result
    }

    // MARK: - Placement

    /// Gives `card` a sort index at `slot` within `others` (which must not
    /// contain it) and stores it. If the neighbours are too close, renumbers
    /// the whole column and records those cards in `diff`.
    private mutating func place(_ card: inout TaskCard, in others: [TaskCard], at slot: Int, diff: inout CardDiff) {
        let before = slot > 0 ? others[slot - 1].sortIndex : nil
        let after = slot < others.count ? others[slot].sortIndex : nil
        let index = FractionalIndex.between(before, after)
        if FractionalIndex.isCrowded(index, before: before, after: after) {
            var ordered = others
            ordered.insert(card, at: slot)
            for (offset, var item) in ordered.enumerated() {
                let renumbered = Double(offset + 1)
                if item.id == card.id {
                    card.sortIndex = renumbered
                    cardsByID[card.id] = card
                } else if item.sortIndex != renumbered {
                    let previous = item
                    item.sortIndex = renumbered // bookkeeping only: no updatedAt bump
                    cardsByID[item.id] = item
                    diff.changes[item.id] = CardChange(before: previous, after: item)
                }
            }
        } else {
            card.sortIndex = index
            cardsByID[card.id] = card
        }
    }
}
