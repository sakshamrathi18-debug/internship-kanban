import AppIntents
import Foundation
import KanbanCore

/// The widget's "→" button: To Do → In Progress → Done, On Hold → In Progress.
/// Writes through the same coordinated, merging persistence the app uses; the
/// app notices the change through its file presenter.
struct MoveForwardIntent: AppIntent {
    static let title: LocalizedStringResource = "Move Task Forward"
    static let description = IntentDescription("Moves a task to its next column.")
    static let isDiscoverable = false

    @Parameter(title: "Task")
    var cardID: String

    init() {}

    init(cardID: UUID) {
        self.cardID = cardID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: cardID) else { return .result() }
        try FileBoardPersistence().mutate { board in
            board.widgetMoveForward(id, now: KanbanTime.now())
        }
        return .result()
    }
}
