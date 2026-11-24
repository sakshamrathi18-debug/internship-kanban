import Foundation

/// How the board came back at launch.
public enum LoadOutcome: Equatable, Sendable {
    case loaded(BoardFile)
    /// No file and no backups: first launch, seed data written.
    case seeded(BoardFile)
    /// `board.json` was unreadable (renamed to `corruptFileName`) or missing
    /// (`corruptFileName == nil`), and the newest valid backup was restored.
    case restoredFromBackup(BoardFile, backupDate: Date, corruptFileName: String?)
    /// Unreadable and no valid backup. The bad file is kept under `corruptFileName`.
    case unrecoverable(corruptFileName: String)
    /// Saved by a newer app version: show it (if decodable) but never write.
    case newerSchema(BoardFile?, version: Int)
    /// The file exists but can't be opened at all (permissions). Read-only.
    case inaccessible
}

/// The file's current state, for re-reading after an outside change.
public enum DiskState: Sendable {
    case board(BoardFile)
    case missing
    case unreadable
    case newerSchema(version: Int, BoardFile?)
}

public enum PersistenceError: Error, Equatable {
    case newerSchema(version: Int)
    case unreadable
}

/// Storage behind the store. The file implementation is the only one in v1;
/// keeping it behind a protocol leaves room for sync later without UI changes.
public protocol BoardPersistence: AnyObject, Sendable {
    func load(seed: @Sendable () -> BoardFile) -> LoadOutcome
    func read() async -> DiskState
    /// Read the file, merge `board` into it (newer `updatedAt` wins), write
    /// atomically. Returns what was written. Runs off the main thread.
    func save(_ board: Board, deletedIDs: Set<UUID>) async throws -> Board
    /// Same as `save`, but blocks: used on quit so nothing is lost.
    func saveNow(_ board: Board, deletedIDs: Set<UUID>) throws -> Board
    /// Import: back up whatever is there, then write `file` as-is.
    func replace(with file: BoardFile) throws
    func startObserving(_ onChange: @escaping @Sendable () -> Void)
    func stopObserving()
}
