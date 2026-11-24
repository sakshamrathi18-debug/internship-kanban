import KanbanCore
import SwiftUI

/// Menu bar: Undo/Redo routed to the board, New Task (⌘N), Find (⌘F), and a
/// Task menu with the keyboard moves.
struct BoardCommands: Commands {
    let model: AppModel

    var body: some Commands {
        let store = model.store
        let ui = model.ui
        let selected = ui.selectedCardID.flatMap { store.card($0) }
        let canAct = selected != nil && !store.isReadOnly
        let animation = Motion.spring(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)

        CommandGroup(replacing: .undoRedo) {
            Button(store.undoState.canUndo ? "Undo \(store.undoState.undoName)" : "Undo") { model.performUndo() }
                .keyboardShortcut("z")
            Button(store.undoState.canRedo ? "Redo \(store.undoState.redoName)" : "Redo") { model.performRedo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .newItem) {
            Button("New Task") { ui.openComposer(.todo) }
                .keyboardShortcut("n")
                .disabled(store.isReadOnly)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Find…") { ui.showSearch() }
                .keyboardShortcut("f")
        }

        CommandGroup(after: .toolbar) {
            Button("Show Archive") { ui.showArchive = true }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Toggle("Show Summary in Toolbar", isOn: Binding(
                get: { store.settings.showSummaryStrip },
                set: { value in store.updateSettings { $0.showSummaryStrip = value } }
            ))
            Divider()
        }

        CommandMenu("Task") {
            // Space and Delete work on the board directly; they aren't menu
            // shortcuts so they never steal keys from a text field.
            Button("Edit Task") { if let id = selected?.id { ui.openEditor(id) } }
                .disabled(selected == nil)
            Divider()
            Button("Move to Next Column") {
                if let id = selected?.id { withAnimation(animation) { _ = store.moveToAdjacentColumn(id, forward: true) } }
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(!canAct || selected?.column.next == nil)
            Button("Move to Previous Column") {
                if let id = selected?.id { withAnimation(animation) { _ = store.moveToAdjacentColumn(id, forward: false) } }
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(!canAct || selected?.column.previous == nil)
            Button("Move Up") {
                if let id = selected?.id { withAnimation(animation) { _ = store.reorder(id, by: -1) } }
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(!canAct)
            Button("Move Down") {
                if let id = selected?.id { withAnimation(animation) { _ = store.reorder(id, by: 1) } }
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(!canAct)
            Menu("Move To") {
                ForEach(Column.allCases) { column in
                    Button(column.title) {
                        if let id = selected?.id { withAnimation(animation) { _ = store.moveToTop(id, of: column) } }
                    }
                    .disabled(selected?.column == column)
                }
            }
            .disabled(!canAct)
            Menu("Set Priority") {
                ForEach(Priority.editorOrder.reversed()) { priority in
                    Button(priority.title) { if let id = selected?.id { store.setPriority(id, priority) } }
                }
            }
            .disabled(!canAct)
            Divider()
            Button("Duplicate") {
                if let id = selected?.id { withAnimation(animation) { _ = store.duplicate(id) } }
            }
            .keyboardShortcut("d")
            .disabled(!canAct)
            Button("Delete") {
                if let id = selected?.id { ui.delete(id, in: store, animation: animation) }
            }
            .disabled(!canAct)
        }
    }
}
