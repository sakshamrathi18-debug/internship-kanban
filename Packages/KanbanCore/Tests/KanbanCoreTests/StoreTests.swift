import Foundation
import Testing
@testable import KanbanCore

@MainActor
@Suite("Store")
struct StoreTests {
    let clock = TestClock(Fixtures.saturdayEvening)

    func memoryStore(_ cards: [TaskCard] = []) -> BoardStore {
        BoardStore(persistence: nil, now: clock.function, calendar: Fixtures.istCalendar, initial: BoardFile(cards: cards))
    }

    func fileStore(_ dir: URL) -> BoardStore {
        let store = BoardStore(persistence: FileBoardPersistence(directory: dir, now: clock.function), now: clock.function, calendar: Fixtures.istCalendar)
        store.saveDelay = .milliseconds(20)
        return store
    }

    func tick() { clock.advance(seconds: 1) }

    /// Waits (up to 5 s) for debounced saves to reach the disk. Store tests
    /// share the main actor, so a fixed sleep isn't reliable under load.
    func waitForSave(_ store: BoardStore) async throws {
        for _ in 0..<250 where store.hasPendingSave {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!store.hasPendingSave)
    }

    // MARK: Adding

    @Test func whitespaceTitlesAreIgnored() {
        let store = memoryStore()
        #expect(store.addCard("   \n ", to: .todo) == nil)
        #expect(store.todo.isEmpty)
        #expect(!store.undoState.canUndo)
    }

    @Test func tenRapidAddsKeepOrder() {
        let store = memoryStore()
        for i in 1...10 { store.addCard("Task \(i)", to: .todo) }
        #expect(store.todo.map(\.title) == (1...10).map { "Task \($0)" })
    }

    @Test func addParsesQuickSyntax() throws {
        let store = memoryStore()
        let card = try #require(store.addCard("Mock interview prep !med #Prep due:tomorrow", to: .inProgress))
        #expect(card.title == "Mock interview prep")
        #expect(card.priority == .medium)
        #expect(card.category == "Prep")
        #expect(card.dueDate == CalendarDay(year: 2026, month: 10, day: 11))
        #expect(store.lastChange?.kind == .added)
        #expect(store.lastChange?.cardIDs == [card.id])
    }

    @Test func multiLinePasteIsOneUndoStep() {
        let store = memoryStore()
        store.addCards(["One", "Two", "", "Three"], to: .todo)
        #expect(store.todo.map(\.title) == ["One", "Two", "Three"])
        #expect(store.undoState.undoName == "Add 3 Tasks")
        store.undo()
        #expect(store.todo.isEmpty)
    }

    // MARK: Undo / redo

    @Test func undoRedoAddMoveDelete() throws {
        let store = memoryStore()
        let card = try #require(store.addCard("Write cover letter", to: .todo))
        tick()
        #expect(store.move(card.id, to: .inProgress, index: 0))
        tick()
        store.delete(card.id)
        #expect(store.inProgress.isEmpty)

        store.undo() // delete
        #expect(store.inProgress.map(\.title) == ["Write cover letter"])
        store.undo() // move
        #expect(store.todo.map(\.title) == ["Write cover letter"])
        #expect(store.inProgress.isEmpty)
        store.undo() // add
        #expect(store.todo.isEmpty)
        #expect(!store.undoState.canUndo)

        store.redo()
        store.redo()
        #expect(store.inProgress.map(\.title) == ["Write cover letter"])
        store.redo()
        #expect(store.inProgress.isEmpty)
        #expect(store.undoState.canUndo && !store.undoState.canRedo)
    }

    @Test func rapidMovesAreEachUndoable() throws {
        let store = memoryStore()
        let a = try #require(store.addCard("A", to: .todo))
        store.addCard("B", to: .todo)
        for column in [Column.inProgress, .onHold, .done, .todo, .inProgress] {
            tick()
            store.move(a.id, to: column, index: 0)
        }
        #expect(store.inProgress.map(\.title) == ["A"])
        #expect(store.stats.total == 2)
        for _ in 0..<5 { store.undo() }
        #expect(store.todo.map(\.title) == ["A", "B"])
        #expect(store.stats.inProgress == 0)
    }

    @Test func movingIntoDoneAndBackOut() throws {
        let store = memoryStore()
        let card = try #require(store.addCard("Submit form", to: .todo))
        tick()
        store.move(card.id, to: .done, index: 0)
        #expect(store.card(card.id)?.completedAt != nil)
        tick()
        store.move(card.id, to: .todo, index: 0)
        #expect(store.card(card.id)?.completedAt == nil)
        store.undo()
        #expect(store.card(card.id)?.column == .done)
        #expect(store.card(card.id)?.completedAt != nil)
    }

    @Test func sameSpotMoveIsNotRecorded() throws {
        let store = memoryStore()
        let card = try #require(store.addCard("Stay", to: .todo))
        let undoName = store.undoState.undoName
        tick()
        #expect(!store.move(card.id, to: .todo, index: 0))
        #expect(store.card(card.id)?.updatedAt == card.updatedAt)
        #expect(store.undoState.undoName == undoName)
    }

    @Test func editSessionUndoesAsOneStep() throws {
        let store = memoryStore()
        let card = try #require(store.addCard("Draft", to: .todo))
        store.beginEditing(card.id)
        for letter in ["D", "Dr", "Dra", "Draf", "Draft email"] {
            tick()
            store.edit(card.id) { $0.title = letter }
        }
        store.edit(card.id) { $0.priority = .high }
        store.editColumn(card.id, to: .onHold)
        store.edit(card.id) { $0.waitingOn = "Reply from HR" }
        store.endEditing()
        #expect(store.onHold.first?.title == "Draft email")
        #expect(store.undoState.undoName == "Edit")

        store.undo()
        let restored = try #require(store.card(card.id))
        #expect(restored.title == "Draft")
        #expect(restored.priority == .none)
        #expect(restored.column == .todo)
        #expect(restored.waitingOn.isEmpty)
        store.redo()
        #expect(store.card(card.id)?.title == "Draft email")
    }

    @Test func emptiedTitleSnapsBackWhenEditingEnds() throws {
        let store = memoryStore()
        let card = try #require(store.addCard("Keep me", to: .todo))
        store.edit(card.id) { $0.title = "   " }
        store.endEditing()
        #expect(store.card(card.id)?.title == "Keep me")
    }

    @Test func toastUndoRestoresDeletedCard() throws {
        let store = memoryStore()
        let card = try #require(store.addCard("Post infographic on LinkedIn", to: .todo))
        store.addCard("Other", to: .todo)
        let deleted = try #require(store.delete(card.id))
        store.undoDeletion(of: deleted)
        #expect(store.todo.map(\.title) == ["Post infographic on LinkedIn", "Other"])

        // When something else happened since, the card still comes back.
        store.delete(card.id)
        store.addCard("Newer action", to: .todo)
        store.undoDeletion(of: deleted)
        #expect(store.todo.contains { $0.id == card.id })
    }

    // MARK: Archive

    @Test func archivesOnLaunchAndAtMidnight() throws {
        var old = Fixtures.card("Old done", .done, 1, at: Fixtures.saturdayEvening.addingTimeInterval(-20 * 86_400))
        old.completedAt = old.createdAt
        var nearly = Fixtures.card("Nearly", .done, 2, at: Fixtures.saturdayEvening.addingTimeInterval(-14 * 86_400))
        nearly.completedAt = nearly.createdAt
        let store = memoryStore([old, nearly])
        #expect(store.archived.map(\.title) == ["Old done"])
        #expect(store.done.map(\.title) == ["Nearly"])

        clock.advance(seconds: 86_400) // the next day
        store.refreshDay()
        #expect(store.today == Fixtures.saturday.adding(days: 1))
        #expect(store.archived.count == 2)

        store.restoreFromArchive(old.id)
        #expect(store.todo.first?.title == "Old done")
    }

    // MARK: Persistence through the store

    @Test func debouncedSaveReachesDisk() async throws {
        let dir = Fixtures.tempDirectory()
        let store = fileStore(dir)
        store.addCard("Persist me", to: .todo)
        #expect(store.hasPendingSave)
        try await waitForSave(store)
        let reopened = fileStore(dir)
        #expect(reopened.todo.contains { $0.title == "Persist me" })
    }

    @Test func flushWritesImmediately() throws {
        let dir = Fixtures.tempDirectory()
        let store = fileStore(dir)
        store.saveDelay = .seconds(60)
        store.addCard("Right before quit", to: .onHold)
        store.flush()
        let reopened = fileStore(dir)
        #expect(reopened.onHold.map(\.title) == ["Right before quit"])
    }

    @Test func seedOnFirstLaunch() {
        let store = fileStore(Fixtures.tempDirectory())
        #expect(store.inProgress.map(\.title) == ["Complete SIP brochure"])
        // Grouped by priority: High above Medium.
        #expect(store.todo.map(\.title) == ["Recruiter calling — past recruiters' HRs", "Post infographic on LinkedIn"])
        #expect(store.done.isEmpty && store.onHold.isEmpty)
        #expect(store.banner == nil)
    }

    @Test func widgetChangeIsMergedOnReload() async throws {
        let dir = Fixtures.tempDirectory()
        let store = fileStore(dir)
        let infographic = try #require(store.todo.first { $0.title.hasPrefix("Post infographic") })
        clock.advance(seconds: 2)
        let widget = FileBoardPersistence(directory: dir, now: clock.function)
        try widget.mutate { $0.widgetMoveForward(infographic.id, now: clock.now) }

        await store.reloadFromDisk()
        // Top of its own (Medium) group, which sits below the High brochure.
        #expect(store.inProgress.map(\.title) == ["Complete SIP brochure", "Post infographic on LinkedIn"])
        #expect(store.todo.count == 1)
        #expect(store.lastChange?.kind == .external)
        #expect(store.lastChange?.previousColumns[infographic.id] == .todo)
    }

    @Test func deletedFileWhileRunningIsRecreated() async throws {
        let dir = Fixtures.tempDirectory()
        let store = fileStore(dir)
        let url = dir.appendingPathComponent("board.json")
        try FileManager.default.removeItem(at: url)
        await store.reloadFromDisk()
        try await waitForSave(store)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(fileStore(dir).stats.total == 3)
    }

    @Test func corruptFileShowsRestoreBanner() throws {
        let dir = Fixtures.tempDirectory()
        let first = fileStore(dir)
        clock.advance(seconds: 60)
        first.addCard("Before corruption", to: .todo)
        first.flush() // backs up the seed, writes the new card
        try Data("not json".utf8).write(to: dir.appendingPathComponent("board.json"))
        let store = fileStore(dir)
        #expect(store.banner?.kind == .restored)
        #expect(store.banner?.message.hasPrefix("Couldn't read your board, restored from backup at") == true)
        #expect(store.stats.total == 3)
    }

    @Test func newerSchemaOpensReadOnly() throws {
        let dir = Fixtures.tempDirectory()
        var file = Seed.file(now: Fixtures.saturdayEvening)
        file.schemaVersion = 2
        try BoardCoding.encode(file).write(to: dir.appendingPathComponent("board.json"))
        let store = fileStore(dir)
        #expect(store.isReadOnly)
        #expect(store.banner?.kind == .readOnly)
        #expect(store.addCard("Nope", to: .todo) == nil)
        #expect(store.stats.total == 3)
    }

    @Test func importReplacesBoardAndClearsHistory() throws {
        let dir = Fixtures.tempDirectory()
        let store = fileStore(dir)
        store.addCard("Will be replaced", to: .todo)
        try store.importBoard(BoardFile(cards: [Fixtures.card("Imported", .onHold, 1)], settings: BoardSettings(wipLimit: 5)))
        #expect(store.onHold.map(\.title) == ["Imported"])
        #expect(store.todo.isEmpty)
        #expect(store.settings.wipLimit == 5)
        #expect(!store.undoState.canUndo)
        #expect(fileStore(dir).onHold.map(\.title) == ["Imported"])
    }

    @Test func wipNudge() {
        let store = memoryStore()
        for i in 1...3 { store.addCard("WIP \(i)", to: .inProgress) }
        #expect(!store.isOverWIPLimit)
        store.addCard("WIP 4", to: .inProgress)
        #expect(store.isOverWIPLimit)
        store.updateSettings { $0.wipLimit = nil }
        #expect(!store.isOverWIPLimit)
    }

    @Test func fiveHundredCardsStayFast() {
        let store = memoryStore()
        let titles = (1...500).map { "Card \($0)" }
        let start = Date()
        for (i, title) in titles.enumerated() {
            store.addCard(title, to: Column.allCases[i % 4])
        }
        let elapsed = Date().timeIntervalSince(start)
        print("500 adds took \(elapsed)s")
        #expect(store.stats.total == 500)
        #expect(elapsed < 5)
        let first = store.todo[0]
        let moveStart = Date()
        store.move(first.id, to: .done, index: 60)
        #expect(Date().timeIntervalSince(moveStart) < 0.05)
    }
}
