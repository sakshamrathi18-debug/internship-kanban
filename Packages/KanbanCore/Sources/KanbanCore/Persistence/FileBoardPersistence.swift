import Foundation

/// `board.json` in the App Group container, plus `backups/`.
///
/// - Every read and write is coordinated (`NSFileCoordinator`), so the app
///   and the widget's intent never interleave.
/// - Writes are atomic (temp file, then rename) and merge with what's on disk
///   first, so a widget move made a moment ago is never overwritten.
/// - A file that won't decode is never overwritten: it's renamed
///   `board.corrupt-<timestamp>.json` and the newest valid backup is used.
/// - A file from a newer schema is never written to.
public final class FileBoardPersistence: BoardPersistence, @unchecked Sendable {
    public static let backupLimit = 5
    /// A new rolling backup at most this often, so five backups span real
    /// history rather than the last few seconds of typing.
    public static let backupInterval: TimeInterval = 10 * 60

    public let directory: URL
    public var boardURL: URL { directory.appendingPathComponent("board.json") }
    public var backupsURL: URL { directory.appendingPathComponent("backups", isDirectory: true) }

    private let queue = DispatchQueue(label: "com.sakshamrathi.InternshipKanban.persistence", qos: .utility)
    private let presenter: BoardFilePresenter
    private let now: @Sendable () -> Date

    public init(directory: URL = AppGroup.dataDirectory(), now: @escaping @Sendable () -> Date = { KanbanTime.now() }) {
        self.directory = directory
        self.now = now
        presenter = BoardFilePresenter(directory: directory)
    }

    deinit {
        stopObserving()
    }

    // MARK: - BoardPersistence

    public func load(seed: @Sendable () -> BoardFile) -> LoadOutcome {
        queue.sync {
            var outcome = LoadOutcome.inaccessible
            coordinateWrite { url in
                switch Self.readData(at: url) {
                case .missing:
                    if let (file, date) = newestValidBackup() {
                        try? write(file, to: url)
                        outcome = .restoredFromBackup(file, backupDate: date, corruptFileName: nil)
                    } else {
                        let file = Board(file: seed()).file
                        try? write(file, to: url)
                        outcome = .seeded(file)
                    }
                case .failed:
                    outcome = .inaccessible
                case .data(let data):
                    switch BoardCoding.decode(data) {
                    case .board(let file):
                        outcome = .loaded(file)
                    case .newerSchema(let version, let file):
                        outcome = .newerSchema(file, version: version)
                    case .corrupt:
                        guard let name = try? preserveCorruptFile(at: url) else {
                            outcome = .inaccessible
                            return
                        }
                        if let (file, date) = newestValidBackup() {
                            try? write(file, to: url)
                            outcome = .restoredFromBackup(file, backupDate: date, corruptFileName: name)
                        } else {
                            outcome = .unrecoverable(corruptFileName: name)
                        }
                    }
                }
            }
            return outcome
        }
    }

    public func read() async -> DiskState {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.readOnQueue())
            }
        }
    }

    /// Blocking read, for the widget's timeline provider.
    public func readNow() -> DiskState {
        queue.sync { readOnQueue() }
    }

    /// The newest backup that decodes, for the widget's "last good snapshot".
    public func newestBackup() -> BoardFile? {
        queue.sync { newestValidBackup()?.0 }
    }

    public func save(_ board: Board, deletedIDs: Set<UUID>) async throws -> Board {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try self.saveOnQueue(board, deletedIDs: deletedIDs) })
            }
        }
    }

    public func saveNow(_ board: Board, deletedIDs: Set<UUID>) throws -> Board {
        try queue.sync { try saveOnQueue(board, deletedIDs: deletedIDs) }
    }

    public func replace(with file: BoardFile) throws {
        try queue.sync {
            var thrown: Error?
            coordinateWrite { url in
                do {
                    if case .data(let data) = Self.readData(at: url) {
                        try writeBackup(data)
                    }
                    try write(file, to: url)
                } catch {
                    thrown = error
                }
            }
            if let thrown { throw thrown }
        }
    }

    /// For the widget's "→": read, change, write, all under one coordinated
    /// write. Returns nil if there's no readable board or `change` did nothing.
    @discardableResult
    public func mutate(_ change: (inout Board) -> CardDiff?) throws -> Board? {
        try queue.sync {
            var result: Board?
            var thrown: Error?
            coordinateWrite { url in
                guard case .data(let data) = Self.readData(at: url), case .board(let file) = BoardCoding.decode(data) else { return }
                var board = Board(file: file)
                guard change(&board) != nil else { return }
                do {
                    try backupIfDue(data)
                    try write(board.file, to: url)
                    result = board
                } catch {
                    thrown = error
                }
            }
            if let thrown { throw thrown }
            return result
        }
    }

    public func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        presenter.handler = onChange
        NSFileCoordinator.addFilePresenter(presenter)
    }

    public func stopObserving() {
        guard presenter.handler != nil else { return }
        presenter.handler = nil
        NSFileCoordinator.removeFilePresenter(presenter)
    }

    // MARK: - Reading

    enum RawRead {
        case missing
        case data(Data)
        case failed
    }

    static func readData(at url: URL) -> RawRead {
        do {
            return .data(try Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return .missing
        } catch {
            return FileManager.default.fileExists(atPath: url.path) ? .failed : .missing
        }
    }

    private func readOnQueue() -> DiskState {
        var state = DiskState.missing
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: presenter).coordinate(readingItemAt: boardURL, options: [], error: &coordinationError) { url in
            switch Self.readData(at: url) {
            case .missing: state = .missing
            case .failed: state = .unreadable
            case .data(let data):
                switch BoardCoding.decode(data) {
                case .board(let file): state = .board(file)
                case .newerSchema(let version, let file): state = .newerSchema(version: version, file)
                case .corrupt: state = .unreadable
                }
            }
        }
        if coordinationError != nil, case .missing = state, FileManager.default.fileExists(atPath: boardURL.path) {
            return .unreadable
        }
        return state
    }

    // MARK: - Writing

    private func saveOnQueue(_ board: Board, deletedIDs: Set<UUID>) throws -> Board {
        var result = board
        var thrown: Error?
        coordinateWrite { url in
            do {
                switch Self.readData(at: url) {
                case .missing:
                    break // deleted while running, or never written: recreate from memory
                case .failed:
                    throw PersistenceError.unreadable
                case .data(let data):
                    switch BoardCoding.decode(data) {
                    case .board(let file):
                        let disk = Board(file: file)
                        result = Board.merge(memory: board, disk: disk, deletedIDs: deletedIDs)
                        if result == disk { return } // nothing new to write
                        try backupIfDue(data)
                    case .newerSchema(let version, _):
                        throw PersistenceError.newerSchema(version: version)
                    case .corrupt:
                        _ = try preserveCorruptFile(at: url)
                    }
                }
                try write(result.file, to: url)
            } catch {
                thrown = error
            }
        }
        if let thrown { throw thrown }
        return result
    }

    private func coordinateWrite(_ body: (URL) -> Void) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: presenter).coordinate(writingItemAt: boardURL, options: .forMerging, error: &coordinationError, byAccessor: body)
    }

    /// Always writes cards in board order (column, then position), so the
    /// file is stable and readable.
    private func write(_ file: BoardFile, to url: URL) throws {
        let data = try BoardCoding.encode(Board(file: file).file)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Backups

    private func backupIfDue(_ currentData: Data) throws {
        let now = now()
        if let newest = backupFiles().first, let date = Self.backupDate(from: newest.lastPathComponent),
           now.timeIntervalSince(date) < Self.backupInterval, date <= now.addingTimeInterval(60) {
            return
        }
        try writeBackup(currentData)
    }

    private func writeBackup(_ data: Data) throws {
        try FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        var name = "board-\(Self.stamp(now())).json"
        var counter = 2
        while FileManager.default.fileExists(atPath: backupsURL.appendingPathComponent(name).path) {
            name = "board-\(Self.stamp(now()))-\(counter).json"
            counter += 1
        }
        try data.write(to: backupsURL.appendingPathComponent(name), options: .atomic)
        for old in backupFiles().dropFirst(Self.backupLimit) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    /// Newest first.
    func backupFiles() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: backupsURL.path)) ?? []
        return names
            .filter { $0.hasPrefix("board-") && $0.hasSuffix(".json") }
            .sorted(by: >)
            .map { backupsURL.appendingPathComponent($0) }
    }

    private func newestValidBackup() -> (BoardFile, Date)? {
        for url in backupFiles() {
            guard let data = try? Data(contentsOf: url), case .board(let file) = BoardCoding.decode(data) else { continue }
            let date = Self.backupDate(from: url.lastPathComponent)
                ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? now()
            return (file, date)
        }
        return nil
    }

    private func preserveCorruptFile(at url: URL) throws -> String {
        var name = "board.corrupt-\(Self.stamp(now())).json"
        var counter = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
            name = "board.corrupt-\(Self.stamp(now()))-\(counter).json"
            counter += 1
        }
        try FileManager.default.moveItem(at: url, to: directory.appendingPathComponent(name))
        return name
    }

    // "2026-10-10T21-05-33" in local time, matching what the banner shows.
    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter
    }

    static func stamp(_ date: Date) -> String {
        formatter().string(from: date)
    }

    static func backupDate(from fileName: String) -> Date? {
        // board-2026-10-10T21-05-33.json or board-2026-10-10T21-05-33-2.json
        let body = fileName.dropFirst("board-".count).prefix(19)
        return formatter().date(from: String(body))
    }
}

/// Watches the data directory for changes made by other processes (the
/// widget's intent). Our own coordinated writes pass this presenter, so they
/// don't echo back.
final class BoardFilePresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private let lock = NSLock()
    private var _handler: (@Sendable () -> Void)?

    var handler: (@Sendable () -> Void)? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    init(directory: URL) {
        presentedItemURL = directory
        super.init()
    }

    private func notify() { handler?() }

    func presentedItemDidChange() { notify() }

    func presentedSubitemDidChange(at url: URL) {
        if url.lastPathComponent == "board.json" { notify() }
    }

    func presentedSubitemDidAppear(at url: URL) {
        if url.lastPathComponent == "board.json" { notify() }
    }

    func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping @Sendable (Error?) -> Void) {
        completionHandler(nil)
        if url.lastPathComponent == "board.json" { notify() }
    }
}
