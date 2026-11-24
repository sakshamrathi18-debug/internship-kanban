import Foundation
import Testing
@testable import KanbanCore

@Suite("Persistence")
struct PersistenceTests {
    let clock = TestClock(Fixtures.saturdayEvening)

    func makePersistence(_ dir: URL) -> FileBoardPersistence {
        FileBoardPersistence(directory: dir, now: clock.function)
    }

    func seed() -> BoardFile { Seed.file(now: Fixtures.saturdayEvening) }

    @Test func firstLaunchWritesSeedOnly() throws {
        let dir = Fixtures.tempDirectory()
        let persistence = makePersistence(dir)
        guard case .seeded(let file) = persistence.load(seed: { Seed.file(now: Fixtures.saturdayEvening) }) else {
            Issue.record("expected seed"); return
        }
        #expect(file.cards.count == 3)
        #expect(FileManager.default.fileExists(atPath: persistence.boardURL.path))
        #expect(persistence.backupFiles().isEmpty)
        // Second launch just loads.
        guard case .loaded(let again) = makePersistence(dir).load(seed: { BoardFile(cards: []) }) else {
            Issue.record("expected load"); return
        }
        #expect(again == file)
    }

    @Test func roundTripKeepsOrderUnicodeAndDates() throws {
        let dir = Fixtures.tempDirectory()
        let persistence = makePersistence(dir)
        _ = persistence.load(seed: { BoardFile(cards: []) })
        var board = Board()
        board.add(title: "पहला काम 🎯", column: .todo, now: clock.now) { $0.dueDate = CalendarDay(year: 2026, month: 10, day: 14) }
        board.add(title: "Second", column: .todo, now: clock.now.addingTimeInterval(0.123))
        board.add(title: "Top", column: .todo, position: .top, now: clock.now)
        _ = try persistence.saveNow(board, deletedIDs: [])
        guard case .loaded(let file) = makePersistence(dir).load(seed: { BoardFile(cards: []) }) else {
            Issue.record("expected load"); return
        }
        let loaded = Board(file: file)
        #expect(loaded.titles(.todo) == ["Top", "पहला काम 🎯", "Second"])
        #expect(loaded.cards(in: .todo)[1].dueDate == CalendarDay(year: 2026, month: 10, day: 14))
        // Millisecond precision survives, so updatedAt comparisons stay meaningful.
        let second = try #require(loaded.cards(in: .todo).last)
        #expect(abs(second.createdAt.timeIntervalSince(clock.now.addingTimeInterval(0.123))) < 0.002)
    }

    @Test func corruptFileIsRenamedAndNewestBackupRestored() throws {
        let dir = Fixtures.tempDirectory()
        let persistence = makePersistence(dir)
        _ = persistence.load(seed: { Seed.file(now: Fixtures.saturdayEvening) })
        // Two saves 11 minutes apart → two backups.
        var board = Board(file: seed())
        board.add(title: "Saved before backup 1", column: .todo, now: clock.now)
        _ = try persistence.saveNow(board, deletedIDs: [])
        clock.advance(seconds: 11 * 60)
        board.add(title: "Saved before backup 2", column: .todo, now: clock.now)
        _ = try persistence.saveNow(board, deletedIDs: [])
        #expect(persistence.backupFiles().count == 2)

        try Data("{ this is not json".utf8).write(to: persistence.boardURL)
        clock.advance(seconds: 60)
        let outcome = makePersistence(dir).load(seed: { BoardFile(cards: []) })
        guard case .restoredFromBackup(let file, _, let corruptName?) = outcome else {
            Issue.record("expected restore, got \(outcome)"); return
        }
        // The newest backup holds the board as it was before the second save.
        #expect(Board(file: file).titles(.todo).contains("Saved before backup 1"))
        #expect(corruptName.hasPrefix("board.corrupt-"))
        let preserved = try String(contentsOf: dir.appendingPathComponent(corruptName), encoding: .utf8)
        #expect(preserved == "{ this is not json") // never overwritten
        // board.json is valid again.
        guard case .loaded = makePersistence(dir).load(seed: { BoardFile(cards: []) }) else {
            Issue.record("board.json should be valid after restore"); return
        }
    }

    @Test func corruptWithNoBackupIsUnrecoverableButPreserved() throws {
        let dir = Fixtures.tempDirectory()
        let persistence = makePersistence(dir)
        try Data("garbage".utf8).write(to: persistence.boardURL)
        guard case .unrecoverable(let name) = persistence.load(seed: { Seed.file(now: Fixtures.saturdayEvening) }) else {
            Issue.record("expected unrecoverable"); return
        }
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path))
        #expect(!FileManager.default.fileExists(atPath: persistence.boardURL.path)) // not seeded over
    }

    @Test func newerSchemaIsReadOnlyAndNeverWritten() throws {
        let dir = Fixtures.tempDirectory()
        let persistence = makePersistence(dir)
        var newer = seed()
        newer.schemaVersion = 7
        let original = try BoardCoding.encode(newer)
        try original.write(to: persistence.boardURL)
        guard case .newerSchema(let file?, 7) = persistence.load(seed: { BoardFile(cards: []) }) else {
            Issue.record("expected newer schema"); return
        }
        #expect(file.cards.count == 3)
        #expect(throws: PersistenceError.newerSchema(version: 7)) {
            _ = try persistence.saveNow(Board(), deletedIDs: [])
        }
        #expect(try Data(contentsOf: persistence.boardURL) == original)
    }

    @Test func deletedFileIsRecreatedOnNextSave() throws {
        let dir = Fixtures.tempDirectory()
        let persistence = makePersistence(dir)
        _ = persistence.load(seed: { Seed.file(now: Fixtures.saturdayEvening) })
        try FileManager.default.removeItem(at: persistence.boardURL)
        let board = Board(file: seed())
        _ = try persistence.saveNow(board, deletedIDs: [])
        guard case .loaded(let file) = makePersistence(dir).load(seed: { BoardFile(cards: []) }) else {
            Issue.record("expected file to be recreated"); return
        }
        #expect(file.cards.count == 3)
    }

    @Test func missingFileWithBackupsRestoresInsteadOfSeeding() throws {
        let dir = Fixtures.tempDirectory()
        let persistence = makePersistence(dir)
        _ = persistence.load(seed: { Seed.file(now: Fixtures.saturdayEvening) })
        var board = Board(file: seed())
        board.add(title: "Mine", column: .todo, now: clock.now)
        _ = try persistence.saveNow(board, deletedIDs: []) // backs up the seed
        try FileManager.default.removeItem(at: persistence.boardURL)
        guard case .restoredFromBackup(_, _, nil) = makePersistence(dir).load(seed: { BoardFile(cards: []) }) else {
            Issue.record("expected restore from backup"); return
        }
    }

    @Test func keepsOnlyFiveRollingBackups() throws {
        let dir = Fixtures.tempDirectory()
        let persistence = makePersistence(dir)
        _ = persistence.load(seed: { Seed.file(now: Fixtures.saturdayEvening) })
        var board = Board(file: seed())
        for i in 0..<8 {
            clock.advance(seconds: 11 * 60)
            board.add(title: "card \(i)", column: .todo, now: clock.now)
            _ = try persistence.saveNow(board, deletedIDs: [])
        }
        let backups = persistence.backupFiles()
        #expect(backups.count == 5)
        #expect(backups.map(\.lastPathComponent) == backups.map(\.lastPathComponent).sorted(by: >))
    }

    @Test func rapidSavesDoNotFloodBackups() throws {
        let dir = Fixtures.tempDirectory()
        let persistence = makePersistence(dir)
        _ = persistence.load(seed: { Seed.file(now: Fixtures.saturdayEvening) })
        var board = Board(file: seed())
        for i in 0..<20 {
            clock.advance(seconds: 1)
            board.add(title: "quick \(i)", column: .todo, now: clock.now)
            _ = try persistence.saveNow(board, deletedIDs: [])
        }
        #expect(persistence.backupFiles().count == 1)
    }

    @Test func saveMergesAWidgetMoveMadeOnDisk() throws {
        let dir = Fixtures.tempDirectory()
        let app = makePersistence(dir)
        guard case .seeded(let file) = app.load(seed: { Seed.file(now: Fixtures.saturdayEvening) }) else { return }
        var appBoard = Board(file: file)
        let infographic = try #require(appBoard.cards(in: .todo).first)

        // The widget's intent (another process) moves the infographic card forward.
        clock.advance(seconds: 5)
        let widget = makePersistence(dir)
        let moved = try widget.mutate { $0.widgetMoveForward(infographic.id, now: clock.now) }
        #expect(moved?[infographic.id]?.column == .inProgress)

        // Meanwhile the app (unaware) added a card, then saves.
        clock.advance(seconds: 1)
        appBoard.add(title: "Added in app", column: .todo, now: clock.now)
        let written = try app.saveNow(appBoard, deletedIDs: [])
        #expect(written[infographic.id]?.column == .inProgress)
        #expect(written.titles(.todo).contains("Added in app"))
        #expect(written.activeCards.count == 4) // nothing lost, nothing duplicated
    }

    @Test func widgetMutateWithoutFileDoesNothing() throws {
        let dir = Fixtures.tempDirectory()
        let widget = makePersistence(dir)
        #expect(try widget.mutate { $0.widgetMoveForward(UUID(), now: clock.now) } == nil)
        #expect(!FileManager.default.fileExists(atPath: widget.boardURL.path))
    }

    @Test func replaceBacksUpFirst() throws {
        let dir = Fixtures.tempDirectory()
        let persistence = makePersistence(dir)
        _ = persistence.load(seed: { Seed.file(now: Fixtures.saturdayEvening) })
        try persistence.replace(with: BoardFile(cards: [Fixtures.card("Imported", .todo, 1)]))
        #expect(persistence.backupFiles().count == 1)
        let backup = try Data(contentsOf: persistence.backupFiles()[0])
        guard case .board(let backedUp) = BoardCoding.decode(backup) else { Issue.record("bad backup"); return }
        #expect(backedUp.cards.count == 3)
    }

    @Test func tolerantDecodingOfSparseCards() throws {
        let json = """
        {"schemaVersion":1,"cards":[{"id":"\(UUID().uuidString)","title":"Hand-written","column":"onHold"}]}
        """
        guard case .board(let file) = BoardCoding.decode(Data(json.utf8)) else { Issue.record("should decode"); return }
        #expect(file.cards[0].priority == .none)
        #expect(file.settings == BoardSettings())
    }

    @Test func wipLimitOffSurvivesRoundTrip() throws {
        let data = try BoardCoding.encode(BoardFile(cards: [], settings: BoardSettings(wipLimit: nil)))
        guard case .board(let file) = BoardCoding.decode(data) else { Issue.record("should decode"); return }
        #expect(file.settings.wipLimit == nil)
    }
}

@Suite("Timestamps")
struct TimestampTests {
    @Test func memoryAndDiskAgreeExactly() throws {
        for _ in 0..<500 {
            let date = KanbanTime.round(Date(timeIntervalSince1970: Double.random(in: 1_700_000_000...1_900_000_000)))
            let card = TaskCard(title: "x", column: .todo, sortIndex: 1, createdAt: date)
            let data = try BoardCoding.encode(BoardFile(cards: [card]))
            guard case .board(let file) = BoardCoding.decode(data) else { Issue.record("decode"); return }
            #expect(file.cards[0].createdAt == date)
        }
    }

    @Test func acceptsWholeSecondsAndLongFractions() {
        #expect(BoardCoding.parseISO("2026-10-10T15:51:31Z") == Date(timeIntervalSince1970: 1_791_647_491))
        #expect(BoardCoding.parseISO("2026-10-10T15:51:31.5Z") == KanbanTime.fromMilliseconds(1_791_647_491_500))
        #expect(BoardCoding.parseISO("2026-10-10T15:51:31.123456Z") == KanbanTime.fromMilliseconds(1_791_647_491_123))
        #expect(BoardCoding.isoString(KanbanTime.fromMilliseconds(1_791_647_491_007)) == "2026-10-10T15:51:31.007Z")
    }

    @Test func firstLaunchDoesNotRewriteOrBackUp() async throws {
        let dir = Fixtures.tempDirectory()
        let store = await BoardStore(persistence: FileBoardPersistence(directory: dir))
        await store.reloadFromDisk() // what activation does
        try await Task.sleep(for: .milliseconds(500))
        #expect(await !store.hasPendingSave)
        let backups = (try? FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("backups").path)) ?? []
        #expect(backups.isEmpty)
    }
}
