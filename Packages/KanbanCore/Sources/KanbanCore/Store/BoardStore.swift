import Foundation
import Observation

public struct BoardBanner: Equatable, Sendable, Identifiable {
    public enum Kind: Sendable { case restored, readOnly, saveFailed }

    public let id = UUID()
    public var kind: Kind
    public var message: String
}

/// The most recent change, so the UI can animate it: a glow for new cards,
/// a tint cross-fade for cards that changed column, a scroll into view.
public struct BoardChange: Equatable, Sendable {
    public enum Kind: Sendable { case added, moved, edited, deleted, archived, restored, external, history }

    public let serial: Int
    public let kind: Kind
    public let cardIDs: Set<UUID>
    /// Cards that changed column, mapped to the column they left.
    public let previousColumns: [UUID: Column]
    /// Cards that changed priority (moved between panels), mapped to the old one.
    public var previousPriorities: [UUID: Priority] = [:]
}

public struct UndoState: Equatable, Sendable {
    public var canUndo = false
    public var canRedo = false
    public var undoName = ""
    public var redoName = ""
}

/// The single source of truth for the app. Mutations go through here, so
/// each one is undoable, saved (debounced, off the main thread) and published.
@MainActor
@Observable
public final class BoardStore {
    // One property per column, so a change in To Do doesn't redraw Done.
    public private(set) var todo: [TaskCard] = []
    public private(set) var inProgress: [TaskCard] = []
    public private(set) var onHold: [TaskCard] = []
    public private(set) var done: [TaskCard] = []
    public private(set) var archived: [TaskCard] = []
    public private(set) var stats: BoardStats
    public private(set) var categories: [String] = []
    public private(set) var settings: BoardSettings
    public private(set) var today: CalendarDay
    public private(set) var isReadOnly = false
    public private(set) var lastChange: BoardChange?
    public private(set) var undoState = UndoState()
    public var banner: BoardBanner?

    @ObservationIgnored public let undoManager = UndoManager()
    /// Called after each successful save (the app reloads widget timelines here).
    @ObservationIgnored public var onDidSave: (@MainActor (Board) -> Void)?
    /// Saves happen at most this long after the first unsaved change.
    @ObservationIgnored public var saveDelay: Duration = .milliseconds(300)
    @ObservationIgnored public private(set) var board: Board

    @ObservationIgnored private var deletedIDs: Set<UUID> = []
    @ObservationIgnored private let persistence: BoardPersistence?
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var hasUnsavedChanges = false
    @ObservationIgnored private var savesInFlight = 0
    @ObservationIgnored private var editSession: EditSession?
    @ObservationIgnored private var changeSerial = 0
    @ObservationIgnored private var lastUndoable: (kind: BoardChange.Kind, ids: Set<UUID>)?

    private struct EditSession {
        let id: UUID
        var diff = CardDiff()
    }

    /// - Parameter persistence: nil keeps everything in memory (tests, previews).
    public init(
        persistence: BoardPersistence?,
        now: @escaping @Sendable () -> Date = { KanbanTime.now() },
        calendar: Calendar = .current,
        initial: BoardFile? = nil
    ) {
        self.persistence = persistence
        // Millisecond timestamps match the file exactly (see KanbanTime).
        let now: @Sendable () -> Date = { KanbanTime.round(now()) }
        self.clock = now
        self.calendar = calendar
        today = CalendarDay.today(now: now(), calendar: calendar)
        undoManager.groupsByEvent = false
        undoManager.levelsOfUndo = 200

        var banner: BoardBanner?
        var readOnly = false
        let file: BoardFile
        if let persistence {
            switch persistence.load(seed: { Seed.file(now: now()) }) {
            case .loaded(let loaded), .seeded(let loaded):
                file = loaded
            case .restoredFromBackup(let restored, let date, let corruptName):
                file = restored
                let when = Self.bannerTime(date, now: now())
                banner = BoardBanner(kind: .restored, message: corruptName == nil
                    ? "Your board file was missing, restored from backup at \(when)."
                    : "Couldn't read your board, restored from backup at \(when).")
            case .unrecoverable(let corruptName):
                file = BoardFile(cards: [])
                banner = BoardBanner(kind: .restored, message: "Couldn't read your board and found no backup. The unreadable file was kept as \(corruptName).")
            case .newerSchema(let newer, let version):
                file = newer ?? BoardFile(cards: [])
                readOnly = true
                banner = Self.newerSchemaBanner(version)
            case .inaccessible:
                file = BoardFile(cards: [])
                readOnly = true
                banner = BoardBanner(kind: .readOnly, message: "Couldn't open your board file, so nothing will be saved. Check the file's permissions and relaunch.")
            }
        } else {
            file = initial ?? BoardFile(cards: [])
        }

        board = Board(file: file)
        settings = file.settings
        stats = BoardStats(cards: file.cards, now: now(), calendar: calendar)
        self.banner = banner
        isReadOnly = readOnly
        refreshAllColumns()
        archiveIfDue()
    }

    // MARK: - Reading

    public func cards(in column: Column) -> [TaskCard] {
        switch column {
        case .todo: todo
        case .inProgress: inProgress
        case .onHold: onHold
        case .done: done
        }
    }

    /// A card by id. Reading it registers observation, so views using it
    /// refresh when the card changes.
    public func card(_ id: UUID) -> TaskCard? {
        _ = lastChange
        return board[id]
    }

    public var isOverWIPLimit: Bool {
        BoardStats.isOverWIP(inProgress: inProgress.count, limit: settings.wipLimit)
    }

    public var editingCardID: UUID? { editSession?.id }

    // MARK: - Adding

    /// Adds a card at the bottom of `column`, parsing quick syntax from the
    /// title. Whitespace-only input is ignored (returns nil).
    @discardableResult
    public func addCard(_ rawTitle: String, to column: Column) -> TaskCard? {
        addCards([rawTitle], to: column).first
    }

    /// Several cards as one undo step (multi-line paste).
    @discardableResult
    public func addCards(_ rawTitles: [String], to column: Column) -> [TaskCard] {
        guard !isReadOnly else { return [] }
        endEditing()
        var diff = CardDiff()
        var added: [TaskCard] = []
        for raw in rawTitles {
            let trimmed = TaskCard.cleanTitle(raw)
            guard !trimmed.isEmpty else { continue }
            let parsed = QuickSyntax.parse(trimmed, today: today, existingCategories: board.categories)
            let result = board.add(title: parsed.title, column: column, position: .bottom, now: clock()) { card in
                if let priority = parsed.priority { card.priority = priority }
                if let category = parsed.category { card.category = category }
                if let due = parsed.dueDate { card.dueDate = due }
            }
            diff.append(result.diff)
            added.append(result.card)
        }
        let name = added.count > 1 ? "Add \(added.count) Tasks" : "Add Task"
        commit(diff, kind: .added, undoName: name)
        return added
    }

    @discardableResult
    public func duplicate(_ id: UUID) -> TaskCard? {
        guard !isReadOnly else { return nil }
        endEditing()
        guard let result = board.duplicate(id, now: clock()) else { return nil }
        commit(result.diff, kind: .added, undoName: "Duplicate")
        return result.card
    }

    // MARK: - Moving

    /// Moves to `index` within a priority group of `column`. A different
    /// `priority` (dropping into another panel) changes the card's priority in
    /// the same undo step. Returns false (and touches nothing) if the card is
    /// already there.
    @discardableResult
    public func move(_ id: UUID, to column: Column, priority: Priority? = nil, index: Int) -> Bool {
        guard !isReadOnly else { return false }
        endEditing()
        return commit(board.move(id, to: column, priority: priority, index: index, now: clock()), kind: .moved, undoName: "Move")
    }

    /// "Move to ▸" in the context menu: lands at the top of the column.
    @discardableResult
    public func moveToTop(_ id: UUID, of column: Column) -> Bool {
        guard board[id]?.column != column else { return false }
        return move(id, to: column, index: 0)
    }

    @discardableResult
    public func moveToAdjacentColumn(_ id: UUID, forward: Bool) -> Bool {
        guard !isReadOnly else { return false }
        endEditing()
        return commit(board.moveToAdjacentColumn(id, forward: forward, now: clock()), kind: .moved, undoName: "Move")
    }

    @discardableResult
    public func reorder(_ id: UUID, by offset: Int) -> Bool {
        guard !isReadOnly else { return false }
        endEditing()
        return commit(board.reorder(id, by: offset, now: clock()), kind: .moved, undoName: "Move")
    }

    // MARK: - Editing

    /// A one-off undoable change, e.g. "Set priority ▸" in the context menu.
    public func update(_ id: UUID, actionName: String, _ change: (inout TaskCard) -> Void) {
        guard !isReadOnly else { return }
        endEditing()
        commit(board.update(id, now: clock(), change), kind: .edited, undoName: actionName)
    }

    public func setPriority(_ id: UUID, _ priority: Priority) {
        update(id, actionName: "Set Priority") { $0.priority = priority }
    }

    /// Starts an edit session: every change until `endEditing()` is saved
    /// live but undone as one step.
    public func beginEditing(_ id: UUID) {
        guard editSession?.id != id else { return }
        endEditing()
        editSession = EditSession(id: id)
    }

    /// A live change from the editor (part of the current edit session).
    public func edit(_ id: UUID, _ change: (inout TaskCard) -> Void) {
        guard !isReadOnly else { return }
        beginEditing(id)
        guard let diff = board.update(id, now: clock(), change) else { return }
        editSession?.diff.append(diff)
        commit(diff, kind: .edited, undoName: nil)
    }

    /// The editor's column picker (part of the current edit session).
    public func editColumn(_ id: UUID, to column: Column) {
        guard !isReadOnly, let card = board[id], card.column != column else { return }
        beginEditing(id)
        guard let diff = board.move(id, to: column, index: 0, now: clock()) else { return }
        editSession?.diff.append(diff)
        commit(diff, kind: .moved, undoName: nil)
    }

    /// Closes the edit session and registers it as a single undo step.
    public func endEditing() {
        guard let session = editSession else { return }
        editSession = nil
        var total = session.diff
        // Typing is over: trim the title, and never leave it empty.
        if let card = board[session.id] {
            let cleaned = TaskCard.cleanTitle(card.title)
            let original = TaskCard.cleanTitle(session.diff.changes[session.id]?.before?.title ?? card.title)
            let finalTitle = cleaned.isEmpty ? original : cleaned
            if !finalTitle.isEmpty, finalTitle != card.title,
               let diff = board.update(session.id, now: clock(), { $0.title = finalTitle }) {
                total.append(diff)
                commit(diff, kind: .edited, undoName: nil)
            }
        }
        guard !total.isEmpty else { return }
        registerUndo(total, name: "Edit", kind: .edited)
    }

    // MARK: - Deleting & archive

    @discardableResult
    public func delete(_ id: UUID) -> TaskCard? {
        guard !isReadOnly else { return nil }
        endEditing()
        guard let card = board[id] else { return nil }
        commit(board.delete(id), kind: .deleted, undoName: "Delete")
        return card
    }

    /// The toast's "Undo". If the deletion is still the last thing done, this
    /// is a plain undo; otherwise the card is put back directly.
    public func undoDeletion(of card: TaskCard) {
        guard board[card.id] == nil else { return }
        if let last = lastUndoable, last.kind == .deleted, last.ids == [card.id], undoManager.canUndo {
            undo()
            return
        }
        commit(board.restore([card.id: card], now: clock()), kind: .restored, undoName: "Restore")
    }

    @discardableResult
    public func restoreFromArchive(_ id: UUID) -> Bool {
        guard !isReadOnly else { return false }
        endEditing()
        return commit(board.restoreFromArchive(id, now: clock()), kind: .restored, undoName: "Restore")
    }

    // MARK: - Undo

    public func undo() {
        endEditing()
        guard undoManager.canUndo else { return }
        undoManager.undo()
        lastUndoable = nil
        updateUndoState()
    }

    public func redo() {
        endEditing()
        guard undoManager.canRedo else { return }
        undoManager.redo()
        lastUndoable = nil
        updateUndoState()
    }

    private func registerUndo(_ diff: CardDiff, name: String, kind: BoardChange.Kind) {
        undoManager.beginUndoGrouping()
        registerHistoryStep(diff.inverted, name: name)
        undoManager.endUndoGrouping()
        lastUndoable = (kind, Set(diff.changes.keys))
        updateUndoState()
    }

    /// Registers an action that takes each card in `step` to its `after`.
    /// Running it registers the opposite step, which is how redo works.
    private func registerHistoryStep(_ step: CardDiff, name: String) {
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                store.applyHistoryStep(step, name: name)
            }
        }
        undoManager.setActionName(name)
    }

    private func applyHistoryStep(_ step: CardDiff, name: String) {
        let versions = step.changes.mapValues(\.after)
        let applied = board.restore(versions, now: clock())
        registerHistoryStep(step.inverted, name: name)
        for (id, version) in versions {
            if version == nil { deletedIDs.insert(id) } else { deletedIDs.remove(id) }
        }
        publish(applied, kind: .history)
        scheduleSave()
    }

    private func updateUndoState() {
        let state = UndoState(
            canUndo: undoManager.canUndo,
            canRedo: undoManager.canRedo,
            undoName: undoManager.undoActionName,
            redoName: undoManager.redoActionName
        )
        if state != undoState { undoState = state }
    }

    // MARK: - Settings, import, export

    public func updateSettings(_ change: (inout BoardSettings) -> Void) {
        guard !isReadOnly else { return }
        var updated = settings
        change(&updated)
        guard updated != settings else { return }
        let archiveChanged = updated.archiveAfterDays != settings.archiveAfterDays
        board.settings = updated
        settings = updated
        scheduleSave()
        if archiveChanged { archiveIfDue() }
    }

    public func exportData() throws -> Data {
        try BoardCoding.encode(board.file)
    }

    /// Replaces the whole board. The current file is backed up first.
    public func importBoard(_ file: BoardFile) throws {
        guard !isReadOnly else { return }
        endEditing()
        saveTask?.cancel()
        saveTask = nil
        try persistence?.replace(with: file)
        let previous = board
        board = Board(file: file)
        settings = file.settings
        deletedIDs = Set(previous.cardsByID.keys).subtracting(board.cardsByID.keys)
        hasUnsavedChanges = false
        undoManager.removeAllActions()
        lastUndoable = nil
        updateUndoState()
        var diff = CardDiff()
        for id in Set(previous.cardsByID.keys).union(board.cardsByID.keys) {
            diff.changes[id] = CardChange(before: previous[id], after: board[id])
        }
        publish(diff, kind: .external)
        archiveIfDue()
        onDidSave?(board)
    }

    public func dismissBanner() {
        banner = nil
    }

    // MARK: - Time

    /// Call at midnight, on wake and on time-zone changes: refreshes "Today"
    /// labels and archives old Done cards.
    public func refreshDay() {
        let newToday = CalendarDay.today(now: clock(), calendar: calendar)
        if newToday != today { today = newToday }
        stats = BoardStats(cards: Array(board.cardsByID.values), now: clock(), calendar: calendar)
        archiveIfDue()
    }

    private func archiveIfDue() {
        guard !isReadOnly else { return }
        commit(board.archiveOldDoneCards(today: today, calendar: calendar, now: clock()), kind: .archived, undoName: nil)
    }

    // MARK: - Saving

    /// Writes any pending change immediately (quit, backgrounding).
    public func flush() {
        saveTask?.cancel()
        saveTask = nil
        // Also covers a save already running in the background: saveNow waits
        // for it on the persistence queue, then writes the latest board.
        guard hasUnsavedChanges || savesInFlight > 0, let persistence, !isReadOnly else { return }
        hasUnsavedChanges = false
        do {
            let written = try persistence.saveNow(board, deletedIDs: deletedIDs)
            absorb(written)
            onDidSave?(board)
        } catch {
            handleSaveError(error)
        }
    }

    /// True until every change has actually reached the disk.
    public var hasPendingSave: Bool { hasUnsavedChanges || savesInFlight > 0 }

    private func scheduleSave() {
        guard persistence != nil, !isReadOnly else { return }
        hasUnsavedChanges = true
        // Trailing throttle: the first change starts the clock, so a save is
        // never more than `saveDelay` behind, even during continuous typing.
        guard saveTask == nil else { return }
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.performSave()
        }
    }

    private func performSave() async {
        saveTask = nil
        guard hasUnsavedChanges, let persistence, !isReadOnly else { return }
        hasUnsavedChanges = false
        let snapshot = board
        let deleted = deletedIDs
        savesInFlight += 1
        defer { savesInFlight -= 1 }
        do {
            let written = try await persistence.save(snapshot, deletedIDs: deleted)
            absorb(written)
            if banner?.kind == .saveFailed { banner = nil }
            onDidSave?(board)
        } catch {
            handleSaveError(error)
        }
    }

    private func handleSaveError(_ error: Error) {
        if case PersistenceError.newerSchema(let version) = error {
            isReadOnly = true
            banner = Self.newerSchemaBanner(version)
            return
        }
        hasUnsavedChanges = true
        banner = BoardBanner(kind: .saveFailed, message: "Couldn't save your board. Retrying…")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.scheduleSave()
        }
    }

    // MARK: - Outside changes (the widget)

    /// Starts watching the file for writes from other processes.
    public func startObservingDisk() {
        persistence?.startObserving { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
    }

    public func stopObservingDisk() {
        persistence?.stopObserving()
    }

    /// Coalesces bursts of file notifications into one read.
    public func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await self?.reloadFromDisk()
        }
    }

    /// Re-reads the file and merges it in (newer `updatedAt` wins per card).
    public func reloadFromDisk() async {
        guard let persistence else { return }
        let state = await persistence.read()
        switch state {
        case .board(let file):
            let disk = Board(file: file)
            absorb(disk)
            if Board.merge(memory: board, disk: disk, deletedIDs: deletedIDs) != disk {
                scheduleSave() // memory has things the file doesn't
            }
        case .missing, .unreadable:
            // Deleted or damaged while running: rewrite it from memory. A
            // damaged file is moved aside by the save, never overwritten.
            if !isReadOnly { scheduleSave() }
        case .newerSchema(let version, _):
            isReadOnly = true
            banner = Self.newerSchemaBanner(version)
        }
    }

    private func absorb(_ disk: Board) {
        let merged = Board.merge(memory: board, disk: disk, deletedIDs: deletedIDs)
        guard merged != board else { return }
        var diff = CardDiff()
        for (id, card) in merged.cardsByID where board[id] != card {
            diff.changes[id] = CardChange(before: board[id], after: card)
        }
        board = merged
        publish(diff, kind: .external)
    }

    // MARK: - Plumbing

    @discardableResult
    private func commit(_ diff: CardDiff?, kind: BoardChange.Kind, undoName: String?) -> Bool {
        guard let diff, !diff.isEmpty else { return false }
        for (id, change) in diff.changes {
            if change.after == nil { deletedIDs.insert(id) } else { deletedIDs.remove(id) }
        }
        if let undoName { registerUndo(diff, name: undoName, kind: kind) }
        publish(diff, kind: kind)
        scheduleSave()
        return true
    }

    private func publish(_ diff: CardDiff, kind: BoardChange.Kind) {
        var columns = Set<Column>()
        var archiveChanged = false
        var previousColumns: [UUID: Column] = [:]
        var previousPriorities: [UUID: Priority] = [:]
        for (id, change) in diff.changes {
            for version in [change.before, change.after].compactMap({ $0 }) {
                if version.isArchived { archiveChanged = true } else { columns.insert(version.column) }
            }
            if let before = change.before, let after = change.after, !before.isArchived, before.column != after.column {
                previousColumns[id] = before.column
            }
            if let before = change.before, let after = change.after, !before.isArchived, before.priority != after.priority {
                previousPriorities[id] = before.priority
            }
        }
        for column in columns { refresh(column) }
        if archiveChanged { archived = board.archivedCards }
        let newStats = BoardStats(cards: Array(board.cardsByID.values), now: clock(), calendar: calendar)
        if newStats != stats { stats = newStats }
        let newCategories = board.categories
        if newCategories != categories { categories = newCategories }
        changeSerial += 1
        lastChange = BoardChange(serial: changeSerial, kind: kind, cardIDs: Set(diff.changes.keys),
                                 previousColumns: previousColumns, previousPriorities: previousPriorities)
    }

    private func refresh(_ column: Column) {
        let cards = board.cards(in: column)
        switch column {
        case .todo: if cards != todo { todo = cards }
        case .inProgress: if cards != inProgress { inProgress = cards }
        case .onHold: if cards != onHold { onHold = cards }
        case .done: if cards != done { done = cards }
        }
    }

    private func refreshAllColumns() {
        Column.allCases.forEach(refresh)
        archived = board.archivedCards
        categories = board.categories
        stats = BoardStats(cards: Array(board.cardsByID.values), now: clock(), calendar: calendar)
    }

    private static func newerSchemaBanner(_ version: Int) -> BoardBanner {
        BoardBanner(kind: .readOnly, message: "This board was saved by a newer version of Kanban Board (format \(version)), so it's open read-only.")
    }

    static func bannerTime(_ date: Date, now: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDate(date, inSameDayAs: now) { return time }
        return "\(date.formatted(.dateTime.day().month(.abbreviated))), \(time)"
    }
}
