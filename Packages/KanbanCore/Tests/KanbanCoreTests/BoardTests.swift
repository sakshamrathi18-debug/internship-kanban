import Foundation
import Testing
@testable import KanbanCore

@Suite("Board rules")
struct BoardTests {
    let now = Fixtures.saturdayEvening
    let later = Fixtures.saturdayEvening.addingTimeInterval(60)

    func sampleBoard() -> Board {
        Board(cards: [
            Fixtures.card("A", .todo, 1),
            Fixtures.card("B", .todo, 2),
            Fixtures.card("C", .todo, 3),
            Fixtures.card("P", .inProgress, 1),
        ])
    }

    @Test func addAppendsToBottomAndTop() {
        var board = sampleBoard()
        board.add(title: "D", column: .todo, now: now)
        board.add(title: "Z", column: .todo, position: .top, now: now)
        #expect(board.titles(.todo) == ["Z", "A", "B", "C", "D"])
    }

    @Test func addIntoEmptyColumn() {
        var board = sampleBoard()
        board.add(title: "First", column: .onHold, now: now)
        #expect(board.titles(.onHold) == ["First"])
    }

    @Test func moveAcrossColumnsAtIndex() throws {
        var board = sampleBoard()
        let b = try #require(board.cards(in: .todo).first { $0.title == "B" })
        let diff = board.move(b.id, to: .inProgress, index: 1, now: later)
        #expect(diff != nil)
        #expect(board.titles(.todo) == ["A", "C"])
        #expect(board.titles(.inProgress) == ["P", "B"])
        #expect(board[b.id]?.updatedAt == later)
    }

    @Test func moveIntoEmptyColumnAndToVeryTopAndBottom() throws {
        var board = sampleBoard()
        let a = try #require(board.cards(in: .todo).first)
        board.move(a.id, to: .done, index: 0, now: later)
        #expect(board.titles(.done) == ["A"])
        let c = try #require(board.cards(in: .todo).last)
        board.move(c.id, to: .done, index: 99, now: later) // clamped to the bottom
        #expect(board.titles(.done) == ["A", "C"])
        board.move(c.id, to: .done, index: -5, now: later) // clamped to the top
        #expect(board.titles(.done) == ["C", "A"])
    }

    @Test func droppingInSamePlaceChangesNothing() throws {
        var board = sampleBoard()
        let b = try #require(board.cards(in: .todo)[safe: 1])
        let before = board
        #expect(board.move(b.id, to: .todo, index: 1, now: later) == nil)
        #expect(board == before)
        #expect(board[b.id]?.updatedAt == b.updatedAt)
    }

    @Test func reorderWithinColumn() throws {
        var board = sampleBoard()
        let c = try #require(board.cards(in: .todo).last)
        board.reorder(c.id, by: -1, now: later)
        #expect(board.titles(.todo) == ["A", "C", "B"])
        board.reorder(c.id, by: -1, now: later)
        #expect(board.titles(.todo) == ["C", "A", "B"])
        #expect(board.reorder(c.id, by: -1, now: later) == nil) // already at the top
        board.reorder(c.id, by: 1, now: later)
        #expect(board.titles(.todo) == ["A", "C", "B"])
    }

    @Test func adjacentColumnMovesLandAtTop() throws {
        var board = sampleBoard()
        let a = try #require(board.cards(in: .todo).first)
        board.moveToAdjacentColumn(a.id, forward: true, now: later)
        #expect(board.titles(.inProgress) == ["A", "P"])
        board.moveToAdjacentColumn(a.id, forward: true, now: later)
        #expect(board[a.id]?.column == .onHold)
        board.moveToAdjacentColumn(a.id, forward: true, now: later)
        #expect(board[a.id]?.column == .done)
        #expect(board.moveToAdjacentColumn(a.id, forward: true, now: later) == nil)
        board.moveToAdjacentColumn(a.id, forward: false, now: later)
        #expect(board[a.id]?.column == .onHold)
    }

    @Test func renormalisesWhenGapsGetTiny() throws {
        var board = Board(cards: [Fixtures.card("first", .todo, 1), Fixtures.card("last", .todo, 2)])
        // Keep inserting just below "first": each insert halves the gap.
        var inserted: [String] = []
        for i in 0..<40 {
            let title = "n\(i)"
            let id = board.add(title: title, column: .todo, position: .after(board.cards(in: .todo)[0].id), now: now).card.id
            inserted.insert(title, at: 0)
            #expect(board[id] != nil)
        }
        let cards = board.cards(in: .todo)
        #expect(cards.map(\.title) == ["first"] + inserted + ["last"])
        // Neighbouring indices never collapse below the minimum gap.
        for (a, b) in zip(cards, cards.dropFirst()) {
            #expect(b.sortIndex - a.sortIndex >= FractionalIndex.minimumGap)
        }
    }

    @Test func renormalisationDoesNotBumpUpdatedAt() throws {
        // Two cards with equal indices (e.g. from a hand-edited file) force a renumber.
        let x = Fixtures.card("x", .todo, 5, at: now)
        let y = Fixtures.card("y", .todo, 5, at: now.addingTimeInterval(1))
        var board = Board(cards: [x, y])
        let diff = board.add(title: "between", column: .todo, position: .after(x.id), now: later).diff
        #expect(board.titles(.todo) == ["x", "between", "y"])
        #expect(board.cards(in: .todo).map(\.sortIndex) == [1, 2, 3])
        #expect(board[x.id]?.updatedAt == x.updatedAt)
        #expect(board[y.id]?.updatedAt == y.updatedAt)
        #expect(diff.changes.count == 3) // the new card plus both renumbered neighbours
    }

    @Test func completedAtFollowsDone() throws {
        var board = sampleBoard()
        let a = try #require(board.cards(in: .todo).first)
        board.move(a.id, to: .done, index: 0, now: later)
        #expect(board[a.id]?.completedAt == later)
        board.move(a.id, to: .onHold, index: 0, now: later.addingTimeInterval(5))
        #expect(board[a.id]?.completedAt == nil)
    }

    @Test func cardCreatedInDoneIsCompleted() {
        var board = Board()
        let card = board.add(title: "Already did it", column: .done, now: now).card
        #expect(card.completedAt == now)
    }

    @Test func widgetForwardRules() throws {
        var board = Board(cards: [
            Fixtures.card("todo", .todo, 1),
            Fixtures.card("hold", .onHold, 1),
            Fixtures.card("done", .done, 1),
        ])
        let todo = try #require(board.cards(in: .todo).first)
        board.widgetMoveForward(todo.id, now: later)
        #expect(board[todo.id]?.column == .inProgress)
        board.widgetMoveForward(todo.id, now: later)
        #expect(board[todo.id]?.column == .done) // skips On Hold
        #expect(board[todo.id]?.completedAt == later)

        let hold = try #require(board.cards(in: .onHold).first)
        board.widgetMoveForward(hold.id, now: later)
        #expect(board[hold.id]?.column == .inProgress)

        let done = try #require(board.cards(in: .done).first { $0.title == "done" })
        #expect(board.widgetMoveForward(done.id, now: later) == nil)
    }

    @Test func updateWithoutRealChangeDoesNotBump() throws {
        var board = sampleBoard()
        let a = try #require(board.cards(in: .todo).first)
        #expect(board.update(a.id, now: later) { $0.title = "A" } == nil)
        #expect(board[a.id]?.updatedAt == a.updatedAt)
        #expect(board.update(a.id, now: later) { $0.title = "A2" } != nil)
        #expect(board[a.id]?.updatedAt == later)
    }

    @Test func titleIsCappedAt200() {
        var board = Board()
        let long = String(repeating: "x", count: 260)
        let card = board.add(title: long, column: .todo, now: now).card
        #expect(card.title.count == 200)
        // Capping makes this identical to what's there, so it's not a change.
        #expect(board.update(card.id, now: later) { $0.title = long + "y" } == nil)
        #expect(board[card.id]?.title.count == 200)
    }

    @Test func duplicateTitlesAreDifferentCards() {
        var board = Board()
        let one = board.add(title: "Same", column: .todo, now: now).card
        let two = board.add(title: "Same", column: .todo, now: now).card
        #expect(one.id != two.id)
        #expect(board.titles(.todo) == ["Same", "Same"])
    }

    @Test func duplicateLandsBelowOriginal() throws {
        var board = sampleBoard()
        let a = try #require(board.cards(in: .todo).first)
        let copy = try #require(board.duplicate(a.id, now: later)?.card)
        #expect(board.titles(.todo) == ["A", "A", "B", "C"])
        #expect(board.cards(in: .todo)[1].id == copy.id)
    }

    @Test func categoriesAreDistinctAndSorted() {
        var board = Board()
        board.add(title: "1", column: .todo, now: now) { $0.category = "LinkedIn" }
        board.add(title: "2", column: .todo, now: now) { $0.category = "brochure" }
        board.add(title: "3", column: .todo, now: now) { $0.category = "linkedin" }
        #expect(board.categories == ["brochure", "LinkedIn"])
    }
}

@Suite("Archive rule")
struct ArchiveTests {
    let calendar = Fixtures.istCalendar

    func doneCard(completedDaysAgo days: Int, today: CalendarDay) -> TaskCard {
        let completed = today.adding(days: -days).date(in: calendar).addingTimeInterval(10 * 3600)
        var card = Fixtures.card("done \(days)", .done, Double(days), at: completed)
        card.completedAt = completed
        return card
    }

    @Test func archivesOnlyCardsOlderThanLimit() {
        let today = Fixtures.saturday
        var board = Board(cards: [
            doneCard(completedDaysAgo: 14, today: today),
            doneCard(completedDaysAgo: 15, today: today),
            doneCard(completedDaysAgo: 1, today: today),
        ])
        let diff = board.archiveOldDoneCards(today: today, calendar: calendar, now: Fixtures.saturdayEvening)
        #expect(diff?.changes.count == 1)
        #expect(board.archivedCards.map(\.title) == ["done 15"])
        #expect(board.titles(.done).count == 2)
    }

    @Test func respectsCustomLimit() {
        let today = Fixtures.saturday
        var board = Board(cards: [doneCard(completedDaysAgo: 4, today: today)], settings: BoardSettings(archiveAfterDays: 3))
        board.archiveOldDoneCards(today: today, calendar: calendar, now: Fixtures.saturdayEvening)
        #expect(board.archivedCards.count == 1)
    }

    @Test func clockSetBackwardsNeitherArchivesNorRestores() {
        let today = Fixtures.saturday
        var future = doneCard(completedDaysAgo: -30, today: today) // completed "in the future"
        future.title = "future"
        var alreadyArchived = doneCard(completedDaysAgo: -60, today: today)
        alreadyArchived.isArchived = true
        var board = Board(cards: [future, alreadyArchived])
        #expect(board.archiveOldDoneCards(today: today, calendar: calendar, now: Fixtures.saturdayEvening) == nil)
        #expect(board.titles(.done) == ["future"])
        #expect(board.archivedCards.count == 1)
    }

    @Test func movedOutOfDoneIsNotEligible() throws {
        let today = Fixtures.saturday
        var board = Board(cards: [doneCard(completedDaysAgo: 20, today: today)])
        let card = try #require(board.cards(in: .done).first)
        board.move(card.id, to: .todo, index: 0, now: Fixtures.saturdayEvening)
        #expect(board.archiveOldDoneCards(today: today, calendar: calendar, now: Fixtures.saturdayEvening) == nil)
        #expect(board.titles(.todo) == [card.title])
    }

    @Test func restoreFromArchiveGoesToTopOfToDo() throws {
        let today = Fixtures.saturday
        var board = Board(cards: [doneCard(completedDaysAgo: 20, today: today), Fixtures.card("existing", .todo, 1)])
        board.archiveOldDoneCards(today: today, calendar: calendar, now: Fixtures.saturdayEvening)
        let archived = try #require(board.archivedCards.first)
        board.restoreFromArchive(archived.id, now: Fixtures.saturdayEvening)
        #expect(board.titles(.todo) == [archived.title, "existing"])
        #expect(board[archived.id]?.completedAt == nil)
        #expect(board[archived.id]?.isArchived == false)
    }
}

@Suite("Merge rule")
struct MergeTests {
    let t0 = Fixtures.saturdayEvening

    @Test func newerUpdatedAtWinsPerCard() {
        var mine = Fixtures.card("mine", .todo, 1)
        var theirs = mine
        theirs.column = .inProgress
        theirs.updatedAt = t0.addingTimeInterval(10)
        mine.title = "mine edited"
        mine.updatedAt = t0.addingTimeInterval(5)

        var otherMine = Fixtures.card("other", .todo, 2)
        var otherTheirs = otherMine
        otherTheirs.title = "stale"
        otherTheirs.updatedAt = t0
        otherMine.updatedAt = t0.addingTimeInterval(20)

        let merged = Board.merge(memory: Board(cards: [mine, otherMine]), disk: Board(cards: [theirs, otherTheirs]), deletedIDs: [])
        #expect(merged[mine.id]?.column == .inProgress)
        #expect(merged[mine.id]?.title == "mine")
        #expect(merged[otherMine.id]?.title == "other")
    }

    @Test func tieKeepsMemory() {
        let card = Fixtures.card("x", .todo, 1)
        var disk = card
        disk.sortIndex = 99
        let merged = Board.merge(memory: Board(cards: [card]), disk: Board(cards: [disk]), deletedIDs: [])
        #expect(merged[card.id]?.sortIndex == 1)
    }

    @Test func diskOnlyCardsAreAddedUnlessDeletedHere() {
        let kept = Fixtures.card("from disk", .todo, 1)
        let deleted = Fixtures.card("deleted here", .todo, 2)
        let merged = Board.merge(memory: Board(), disk: Board(cards: [kept, deleted]), deletedIDs: [deleted.id])
        #expect(merged[kept.id] != nil)
        #expect(merged[deleted.id] == nil)
    }

    @Test func memoryOnlyCardsStay() {
        let fresh = Fixtures.card("not saved yet", .todo, 1)
        let merged = Board.merge(memory: Board(cards: [fresh]), disk: Board(), deletedIDs: [])
        #expect(merged[fresh.id] != nil)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

@Suite("Priority groups")
struct PriorityGroupTests {
    let now = Fixtures.saturdayEvening
    let later = Fixtures.saturdayEvening.addingTimeInterval(60)

    func board() -> Board {
        var b = Board()
        b.add(title: "none-1", column: .todo, now: now)
        b.add(title: "high-1", column: .todo, now: now) { $0.priority = .high }
        b.add(title: "low-1", column: .todo, now: now) { $0.priority = .low }
        b.add(title: "high-2", column: .todo, now: now) { $0.priority = .high }
        b.add(title: "med-1", column: .todo, now: now) { $0.priority = .medium }
        return b
    }

    @Test func columnsOrderByPriorityThenPosition() {
        #expect(board().titles(.todo) == ["high-1", "high-2", "med-1", "low-1", "none-1"])
        #expect(board().groups(in: .todo).map(\.priority) == [.high, .medium, .low, .none])
    }

    @Test func droppingIntoAnotherPanelChangesPriority() throws {
        var b = board()
        let none = try #require(b.cards(in: .todo).last)
        let moved = b.move(none.id, to: .todo, priority: .high, index: 1, now: later)
        let diff = try #require(moved)
        #expect(b[none.id]?.priority == .high)
        #expect(b.titles(.todo) == ["high-1", "none-1", "high-2", "med-1", "low-1"])
        #expect(diff.changes[none.id]?.before?.priority == Priority.none)
    }

    @Test func droppingIntoMissingGroupCreatesIt() throws {
        var b = board()
        let med = try #require(b.cards(in: .todo).first { $0.title == "med-1" })
        b.move(med.id, to: .inProgress, priority: .low, index: 0, now: later)
        #expect(b.groups(in: .inProgress).map(\.priority) == [.low])
    }

    @Test func reorderStaysInsideTheGroup() throws {
        var b = board()
        let high2 = try #require(b.cards(in: .todo).first { $0.title == "high-2" })
        #expect(b.reorder(high2.id, by: 1, now: later) == nil) // last of the High group
        b.reorder(high2.id, by: -1, now: later)
        #expect(b.titles(.todo).prefix(2) == ["high-2", "high-1"])
        let med = try #require(b.cards(in: .todo).first { $0.title == "med-1" })
        #expect(b.reorder(med.id, by: -1, now: later) == nil) // never crosses into High
    }

    @Test func changingPriorityLandsAtTopOfNewGroup() throws {
        var b = board()
        let low = try #require(b.cards(in: .todo).first { $0.title == "low-1" })
        b.update(low.id, now: later) { $0.priority = .high }
        #expect(b.titles(.todo).prefix(3) == ["low-1", "high-1", "high-2"])
    }

    @Test func doneIsOneGroupAndKeepsPriority() throws {
        var b = board()
        let high = try #require(b.cards(in: .todo).first)
        let low = try #require(b.cards(in: .todo).first { $0.title == "low-1" })
        b.move(low.id, to: .done, index: 0, now: later)
        b.move(high.id, to: .done, priority: .none, index: 1, now: later)
        #expect(b.titles(.done) == ["low-1", "high-1"])
        #expect(b[high.id]?.priority == .high)
        #expect(b.groups(in: .done).count == 1)
    }

    @Test func newCardLandsAtBottomOfItsGroup() {
        var b = board()
        b.add(title: "high-3", column: .todo, now: later) { $0.priority = .high }
        #expect(b.titles(.todo).prefix(3) == ["high-1", "high-2", "high-3"])
    }
}
