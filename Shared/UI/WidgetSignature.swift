import KanbanCore

extension Board {
    /// A hash of everything the widget shows (titles, columns, order,
    /// priority, dates). Widget reloads are budgeted, so the apps only ask
    /// for one when this changes.
    var widgetSignature: Int {
        var hasher = Hasher()
        for card in file.cards where !card.isArchived {
            hasher.combine(card.id)
            hasher.combine(card.title)
            hasher.combine(card.column)
            hasher.combine(card.sortIndex)
            hasher.combine(card.priority)
            hasher.combine(card.dueDate)
            hasher.combine(card.startDate)
        }
        return hasher.finalize()
    }
}
