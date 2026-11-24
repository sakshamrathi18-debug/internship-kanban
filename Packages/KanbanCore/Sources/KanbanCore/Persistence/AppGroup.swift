import Foundation

/// Where `board.json` lives: the shared App Group container, so the app and
/// the widget read and write the same file.
public enum AppGroup {
    /// Both targets' Info.plist carry the group id (expanded from
    /// `$(DEVELOPMENT_TEAM).com.sakshamrathi.InternshipKanban` at build time).
    public static let infoPlistKey = "KanbanAppGroupIdentifier"

    public static var identifier: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String,
              !id.isEmpty, !id.hasPrefix("$("), !id.hasPrefix(".") else { return nil }
        return id
    }

    /// The directory holding `board.json` and `backups/`.
    public static func dataDirectory() -> URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["KANBAN_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif
        if let id = identifier,
           let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
            return container
        }
        // Unsigned dev builds have no App Group; keep their data separate.
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("InternshipKanban-Dev", isDirectory: true)
    }
}
