import KanbanCore
import SwiftUI

/// One column: its priority panels (High, Medium, Low, No priority; Done is
/// a single "Completed" panel), as a list so rows get native swipe actions.
struct ColumnPage: View {
    let column: Column

    @Environment(BoardStore.self) private var store
    @Environment(PhoneUI.self) private var ui

    private struct Group: Identifiable {
        let priority: Priority
        let cards: [TaskCard]
        var id: Priority { priority }
    }

    private var groups: [Group] {
        let cards = store.cards(in: column)
        if column == .done { return cards.isEmpty ? [] : [Group(priority: .none, cards: cards)] }
        return Priority.boardOrder.compactMap { priority in
            let group = cards.filter { $0.priority == priority }
            return group.isEmpty ? nil : Group(priority: priority, cards: group)
        }
    }

    var body: some View {
        let groups = groups
        List {
            if let note, !PhoneMetrics.hasNavigationSubtitle {
                Text(note.text)
                    .font(.system(size: 13.5, weight: note.warning ? .medium : .regular))
                    .foregroundStyle(note.warning ? Palette.wipWarning : Palette.textTertiary)
                    .plainRow(top: 14, bottom: 0)
            }

            if groups.isEmpty {
                EmptyColumn(column: column)
                    .plainRow(top: 14, bottom: 0)
            }

            ForEach(groups) { group in
                PanelHeader(column: column, priority: group.priority, count: group.cards.count,
                            role: .top)
                    .plainRow(top: 14, bottom: 0)
                ForEach(Array(group.cards.enumerated()), id: \.element.id) { index, card in
                    PhoneCardRow(card: card, role: index == group.cards.count - 1 ? .bottom : .middle, isFirst: index == 0)
                        .plainRow(top: 0, bottom: 0)
                }
            }

            Color.clear.frame(height: 20).plainRow(top: 0, bottom: 0)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .background(Palette.background)
    }

    private var note: (text: String, warning: Bool)? {
        switch column {
        case .inProgress where store.isOverWIPLimit:
            guard let limit = store.settings.wipLimit else { return nil }
            return ("Over your limit of \(limit). Finish one before starting another?", true)
        case .onHold:
            return store.cards(in: .onHold).isEmpty ? nil : ("Started, but waiting on someone or something", false)
        case .done:
            return ("\(store.stats.doneThisWeek) finished this week · archived after \(store.settings.archiveAfterDays) days", false)
        default:
            return nil
        }
    }
}

extension View {
    /// A list row with no chrome: the panels draw their own fill and border.
    func plainRow(top: CGFloat, bottom: CGFloat) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: PhoneMetrics.gutter, bottom: bottom, trailing: PhoneMetrics.gutter))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// An empty column says what belongs there.
private struct EmptyColumn: View {
    let column: Column

    private var hint: String {
        switch column {
        case .todo: return "Tap + to add a task"
        case .inProgress: return "Swipe a To Do task right to start it"
        case .onHold: return "Nothing waiting on anyone"
        case .done: return "Finished tasks land here"
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .frame(height: 110)
            .overlay {
                Text(hint)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Empty. \(hint).")
    }
}

/// A card in its panel: tap to edit, swipe right to move it on, swipe left
/// to delete, long-press for everything else.
struct PhoneCardRow: View {
    let card: TaskCard
    let role: PanelRole
    var isFirst = false
    /// Off for standalone cards (search results); rows in a panel sit under a line.
    var showsTopSeparator = true

    @Environment(BoardStore.self) private var store
    @Environment(PhoneUI.self) private var ui
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var panel: Priority { card.panel }
    private var animation: Animation { Motion.spring(reduceMotion) }

    var body: some View {
        VStack(spacing: 0) {
            if showsTopSeparator {
                Rectangle()
                    .fill(Palette.separator(panel))
                    .frame(height: 1)
            }
            CardContent(card: card, today: store.today)
                .padding(.top, 11)
                .padding(.horizontal, 15)
                .padding(.bottom, 12)
                .background {
                    Palette.ink(panel).opacity(pulse ? 0.12 : 0)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: role.hasTop ? 11 : 0,
                                                          bottomLeadingRadius: role.hasBottom ? 11 : 0,
                                                          bottomTrailingRadius: role.hasBottom ? 11 : 0,
                                                          topTrailingRadius: role.hasTop ? 11 : 0, style: .continuous))
                }
        }
        .background(PanelSegment(priority: panel, role: role))
        .contentShape(Rectangle())
        // Lift just the card (in its panel colours) for the long-press preview.
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { ui.edit(card.id) }
        .swipeActions(edge: .leading, allowsFullSwipe: true) { leadingActions }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                ui.delete(card.id, in: store, animation: animation)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(Palette.accent(.high))
        }
        .contextMenu { menu }
        .onAppear(perform: playArrival)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityDescription(today: store.today))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { ui.edit(card.id) }
        .accessibilityAction(named: "Move to \(card.column.widgetForward?.title ?? "")") { moveForward() }
        .accessibilityAction(named: "Delete") { ui.delete(card.id, in: store, animation: animation) }
    }

    // MARK: - Swipe

    @ViewBuilder
    private var leadingActions: some View {
        if let target = card.column.widgetForward {
            Button { moveForward() } label: {
                Label(forwardLabel(target), systemImage: target == .done ? "checkmark" : "arrow.right")
            }
            .tint(target == .done ? Palette.accent(.low) : Palette.buttonPrimary)
        }
        if card.column == .inProgress {
            Button {
                withAnimation(animation) { _ = store.moveToTop(card.id, of: .onHold) }
            } label: {
                Label("Hold", systemImage: "pause")
            }
            .tint(Palette.accent(.medium))
        }
    }

    private func forwardLabel(_ target: Column) -> String {
        switch target {
        case .inProgress: card.column == .onHold ? "Resume" : "Start"
        case .done: "Done"
        default: target.title
        }
    }

    private func moveForward() {
        guard let target = card.column.widgetForward else { return }
        withAnimation(animation) { _ = store.moveToTop(card.id, of: target) }
    }

    // MARK: - Long-press menu

    @ViewBuilder
    private var menu: some View {
        Button { ui.edit(card.id) } label: { Label("Edit", systemImage: "pencil") }

        Menu {
            ForEach(Column.allCases.filter { $0 != card.column }) { column in
                Button(column.title) {
                    withAnimation(animation) { _ = store.moveToTop(card.id, of: column) }
                }
            }
        } label: {
            Label("Move to", systemImage: "arrow.right.square")
        }

        if card.column != .done {
            Menu {
                ForEach(Priority.boardOrder) { priority in
                    Button {
                        withAnimation(animation) { store.setPriority(card.id, priority) }
                    } label: {
                        if priority == card.priority {
                            Label(priority.title, systemImage: "checkmark")
                        } else {
                            Text(priority.title)
                        }
                    }
                }
            } label: {
                Label("Priority", systemImage: "flag")
            }

            Button {
                withAnimation(animation) { _ = store.reorder(card.id, by: -1) }
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            .disabled(isFirst)
            Button {
                withAnimation(animation) { _ = store.reorder(card.id, by: 1) }
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            .disabled(role.hasBottom)
        }

        Button {
            withAnimation(animation) { _ = store.duplicate(card.id) }
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }

        Divider()
        Button(role: .destructive) {
            ui.delete(card.id, in: store, animation: animation)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func playArrival() {
        guard ui.justAdded.contains(card.id) else { return }
        ui.justAdded.remove(card.id)
        pulse = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: reduceMotion ? 0.4 : 0.9)) { pulse = false }
        }
    }
}
