#if DEBUG
import KanbanCore
import SwiftUI

/// Debug-only hooks for screenshots. `KANBAN_DEMO` opens a screen on launch:
/// editor, composer, archive, settings, toast, or a column
/// (todo, inProgress, onHold, done). Data comes from `KANBAN_DATA_DIR`.
enum PhoneDemo {
    @MainActor
    static func apply(ui: PhoneUI, store: BoardStore) {
        let env = ProcessInfo.processInfo.environment
        if let style = env["KANBAN_APPEARANCE"] {
            let scheme: UIUserInterfaceStyle = style == "dark" ? .dark : .light
            DispatchQueue.main.async {
                for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                    scene.windows.forEach { $0.overrideUserInterfaceStyle = scheme }
                }
            }
        }
        guard let demo = env["KANBAN_DEMO"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let column = Column(rawValue: demo) {
                ui.column = column
                return
            }
            switch demo {
            case "editor":
                if let card = store.cards(in: .todo).first { ui.edit(card.id) }
            case "composer":
                ui.showComposer = true
            case "archive":
                ui.showArchive = true
            case "settings":
                ui.showSettings = true
            case "toast":
                if let card = store.cards(in: .todo).last { ui.delete(card.id, in: store, animation: nil) }
            default:
                break
            }
        }
    }
}
#endif
