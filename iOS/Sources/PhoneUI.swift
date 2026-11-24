import KanbanCore
import Observation
import SwiftUI

/// Screen state that isn't board data: which column is showing, which sheet
/// is open, and the delete toast.
@MainActor
@Observable
final class PhoneUI {
    struct EditorItem: Identifiable, Equatable {
        let id: UUID
    }

    struct DeleteToast: Identifiable, Equatable {
        let id = UUID()
        let card: TaskCard
        let message: String
    }

    /// The tab bar's selection: the column being shown.
    var column: Column = .todo
    var editor: EditorItem?
    var showComposer = false
    var showArchive = false
    var showSettings = false

    var toast: DeleteToast?
    /// Cards added this session pulse once when they first appear.
    var justAdded: Set<UUID> = []

    @ObservationIgnored private var toastDismissal: Task<Void, Never>?

    // MARK: - Navigation

    func edit(_ id: UUID) {
        editor = EditorItem(id: id)
    }

    /// From the widget: switch to the card's column and open it.
    func reveal(_ id: UUID, in store: BoardStore) {
        guard let card = store.card(id), !card.isArchived else { return }
        showComposer = false
        showArchive = false
        showSettings = false
        column = card.column
        edit(id)
    }

    // MARK: - Delete & toast

    func delete(_ id: UUID, in store: BoardStore, animation: Animation?) {
        if editor?.id == id { editor = nil }
        guard let card = withAnimation(animation, { store.delete(id) }) else { return }
        let title = card.title.count > 28 ? String(card.title.prefix(26)).trimmingCharacters(in: .whitespaces) + "…" : card.title
        let toast = DeleteToast(card: card, message: "Deleted ‘\(title)’")
        withAnimation(animation) { self.toast = toast }
        toastDismissal?.cancel()
        toastDismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self, self.toast?.id == toast.id else { return }
            withAnimation(animation) { self.toast = nil }
        }
    }

    func undoDelete(in store: BoardStore, animation: Animation?) {
        guard let toast else { return }
        withAnimation(animation) {
            store.undoDeletion(of: toast.card)
            self.toast = nil
        }
        column = toast.card.column
    }

    func dismissToast() {
        toastDismissal?.cancel()
        toast = nil
    }
}
