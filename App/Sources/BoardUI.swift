import AppKit
import KanbanCore
import Observation
import SwiftUI

/// Window-level UI state that isn't board data: selection, the open composer,
/// the editor, search, toasts, and the short-lived "just arrived" effects.
@MainActor
@Observable
final class BoardUI {
    struct ScrollRequest: Equatable {
        enum Target: Equatable { case card(UUID), composer }
        let column: Column
        let target: Target
        let serial: Int
    }

    /// A card that just landed somewhere: its fill pulses (new), or cross-fades
    /// from the priority panel it left.
    struct Arrival: Equatable {
        var previousPriority: Priority?
        let glow: Bool
    }

    struct DeleteToast: Identifiable, Equatable {
        let id = UUID()
        let card: TaskCard
        let message: String
    }

    enum Direction { case up, down, left, right }

    var selectedCardID: UUID?
    var editingCardID: UUID?
    var composerColumn: Column?
    var composerFocusRequest = 0
    var boardFocusRequest = 0

    var searchVisible = false
    var searchText = ""
    var searchFocusRequest = 0
    var categoryFilter: String?
    /// Cards added while a filter is on stay visible until it's cleared.
    var keepVisible: Set<UUID> = []

    var showArchive = false
    var toast: DeleteToast?
    var scrollRequest: ScrollRequest?
    var arrivals: [UUID: Arrival] = [:]

    @ObservationIgnored private var scrollSerial = 0
    @ObservationIgnored private var suppressedArrivals: Set<UUID> = []
    @ObservationIgnored private var arrivalCleanup: Task<Void, Never>?
    @ObservationIgnored private var toastDismissal: Task<Void, Never>?

    // MARK: - Filter

    var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isFiltering: Bool { !trimmedSearch.isEmpty || categoryFilter != nil }

    func matches(_ card: TaskCard) -> Bool {
        guard isFiltering, !keepVisible.contains(card.id) else { return true }
        if let category = categoryFilter, card.category.caseInsensitiveCompare(category) != .orderedSame {
            return false
        }
        let query = trimmedSearch
        guard !query.isEmpty else { return true }
        return card.title.localizedStandardContains(query)
            || card.nextStep.localizedStandardContains(query)
            || card.category.localizedStandardContains(query)
    }

    func showSearch() {
        searchVisible = true
        searchFocusRequest += 1
    }

    func filter(byCategory category: String) {
        categoryFilter = category
    }

    func clearFilter() {
        searchText = ""
        categoryFilter = nil
        keepVisible = []
        focusBoard()
    }

    // MARK: - Composer & editor

    func openComposer(_ column: Column) {
        editingCardID = nil
        composerColumn = column
        composerFocusRequest += 1
        requestScroll(column, .composer)
    }

    /// Closes the composer, but only if it's still the one in `column`.
    func closeComposer(_ column: Column) {
        guard composerColumn == column else { return }
        composerColumn = nil
    }

    func openEditor(_ id: UUID) {
        selectedCardID = id
        editingCardID = id
    }

    func editorDidClose(_ id: UUID) {
        if editingCardID == id { editingCardID = nil }
        focusBoard()
    }

    func focusBoard() {
        boardFocusRequest += 1
    }

    /// A click on empty board space: drop selection and finish any typing
    /// (the composer keeps what was typed).
    func backgroundTapped() {
        selectedCardID = nil
        editingCardID = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
        focusBoard()
    }

    // MARK: - Selection

    func select(_ id: UUID?) {
        selectedCardID = id
    }

    func moveSelection(_ direction: Direction, in store: BoardStore) {
        let columns = Column.allCases
        guard let id = selectedCardID, let card = store.card(id), !card.isArchived,
              let index = store.cards(in: card.column).firstIndex(where: { $0.id == id }) else {
            if let first = columns.lazy.compactMap({ store.cards(in: $0).first }).first {
                selectedCardID = first.id
                requestScroll(first.column, .card(first.id))
            }
            return
        }
        let list = store.cards(in: card.column)
        switch direction {
        case .up:
            guard index > 0 else { return }
            selectedCardID = list[index - 1].id
        case .down:
            guard index + 1 < list.count else { return }
            selectedCardID = list[index + 1].id
        case .left, .right:
            var column: Column? = direction == .right ? card.column.next : card.column.previous
            while let candidate = column {
                let cards = store.cards(in: candidate)
                if !cards.isEmpty {
                    selectedCardID = cards[min(index, cards.count - 1)].id
                    break
                }
                column = direction == .right ? candidate.next : candidate.previous
            }
        }
        if let selected = selectedCardID, let card = store.card(selected) {
            requestScroll(card.column, .card(selected))
        }
    }

    /// Selects a card and scrolls to it (deep links from the widget).
    func reveal(_ id: UUID, in store: BoardStore) {
        guard let card = store.card(id), !card.isArchived else { return }
        clearFilterIfHiding(card)
        selectedCardID = id
        requestScroll(card.column, .card(id))
        focusBoard()
    }

    private func clearFilterIfHiding(_ card: TaskCard) {
        if isFiltering && !matches(card) { clearFilter() }
    }

    func requestScroll(_ column: Column, _ target: ScrollRequest.Target) {
        scrollSerial += 1
        scrollRequest = ScrollRequest(column: column, target: target, serial: scrollSerial)
    }

    // MARK: - Delete & toast

    func delete(_ id: UUID, in store: BoardStore, animation: Animation?) {
        if editingCardID == id { editingCardID = nil }
        let neighbour = neighbourForSelection(after: id, in: store)
        guard let card = withAnimation(animation, { store.delete(id) }) else { return }
        if selectedCardID == id { selectedCardID = neighbour }
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

    func undoToast(in store: BoardStore, animation: Animation?) {
        guard let toast else { return }
        withAnimation(animation) {
            store.undoDeletion(of: toast.card)
            self.toast = nil
        }
        selectedCardID = toast.card.id
    }

    private func neighbourForSelection(after id: UUID, in store: BoardStore) -> UUID? {
        guard let card = store.card(id) else { return nil }
        let list = store.cards(in: card.column)
        guard let index = list.firstIndex(where: { $0.id == id }) else { return nil }
        if index + 1 < list.count { return list[index + 1].id }
        return index > 0 ? list[index - 1].id : nil
    }

    // MARK: - Reacting to store changes

    /// A drop has already animated the card into place; skip its arrival effect.
    func suppressArrival(of id: UUID) {
        suppressedArrivals.insert(id)
    }

    func handle(_ change: BoardChange?, in store: BoardStore) {
        guard let change else { return }
        var newArrivals = arrivals
        switch change.kind {
        case .added:
            for id in change.cardIDs {
                guard let card = store.card(id) else { continue }
                newArrivals[id] = Arrival(previousPriority: nil, glow: true)
                if isFiltering { keepVisible.insert(id) }
                if composerColumn == card.column {
                    requestScroll(card.column, .composer)
                } else {
                    requestScroll(card.column, .card(id))
                }
            }
        case .moved, .external, .history, .restored:
            for id in change.cardIDs {
                guard let card = store.card(id), !card.isArchived else { continue }
                if suppressedArrivals.remove(id) != nil { continue }
                if let previous = change.previousPriorities[id] {
                    newArrivals[id] = Arrival(previousPriority: previous, glow: false)
                } else if change.kind == .restored {
                    newArrivals[id] = Arrival(previousPriority: nil, glow: true) // back from the archive or a deletion
                }
                if id == selectedCardID {
                    requestScroll(card.column, .card(id))
                }
            }
        case .deleted, .archived:
            if let selected = selectedCardID, store.card(selected) == nil || store.card(selected)?.isArchived == true {
                selectedCardID = nil
            }
            if let editing = editingCardID, store.card(editing) == nil { editingCardID = nil }
        case .edited:
            // A priority change from the editor or menu moves the row to another panel.
            for (id, previous) in change.previousPriorities {
                newArrivals[id] = Arrival(previousPriority: previous, glow: false)
            }
        }
        suppressedArrivals.subtract(change.cardIDs)
        if newArrivals != arrivals {
            arrivals = newArrivals
            arrivalCleanup?.cancel()
            arrivalCleanup = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                self?.arrivals = [:]
            }
        }
    }
}
