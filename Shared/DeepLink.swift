import Foundation

/// `internshipkanban://board` opens the app; `internshipkanban://card/<uuid>`
/// opens it with that card selected. Used by the widget.
enum DeepLink {
    static let scheme = "internshipkanban"
    static let board = URL(string: "\(scheme)://board")!

    static func card(_ id: UUID) -> URL {
        URL(string: "\(scheme)://card/\(id.uuidString)")!
    }

    static func cardID(from url: URL) -> UUID? {
        guard url.scheme == scheme, url.host == "card" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}

/// The widget's kind string; the app reloads it after saves.
enum WidgetKind {
    static let board = "InternshipKanbanWidget"
}
