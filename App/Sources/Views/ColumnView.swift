import KanbanCore
import SwiftUI

/// One column: a pinned serif header over its own vertically scrolling stack
/// of priority panels (High → Medium → Low → No priority; Done is one
/// "Completed" panel). The whole body accepts drops, including when empty.
struct ColumnView: View {
    let column: Column

    @Environment(BoardStore.self) private var store
    @Environment(BoardUI.self) private var ui
    @Environment(DragController.self) private var drag
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A flat list of panel pieces, so the stack stays lazy.
    struct Item: Identifiable, Equatable {
        enum Kind: Equatable {
            case header(count: Int, collapsed: Bool)
            case row(TaskCard)
            case insertion
            case placeholder
            case spacer
        }
        let id: String
        let kind: Kind
        let priority: Priority
        var role: PanelRole = .middle
    }

    var body: some View {
        let cards = store.cards(in: column)
        let items = Self.items(cards: cards, column: column, drag: drag, ui: ui)

        VStack(spacing: 0) {
            ColumnHeader(column: column, count: cards.count)

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            itemView(item)
                                .transition(Motion.cardTransition(reduceMotion))
                        }
                        if items.isEmpty && ui.composerColumn != column {
                            EmptyDropZone(column: column)
                        }
                        if !store.isReadOnly {
                            ComposerSlot(column: column)
                                .padding(.top, items.isEmpty ? 8 : 6)
                                .id(ComposerAnchor(column: column))
                        }
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 16)
                    .animation(Motion.spring(reduceMotion), value: items.map(\.id))
                    .background(ScrollViewProbe { drag.columnScrollViews[column] = WeakScrollView($0) })
                }
                .scrollIndicators(.automatic)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(BoardSpace.viewport)) } action: {
                    drag.bodyFrames[column] = $0
                }
                .onChange(of: ui.scrollRequest) { _, request in
                    scroll(to: request, with: proxy)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(BoardSpace.viewport)) } action: {
            drag.columnFrames[column] = $0
        }
        .contentShape(Rectangle())
        .onTapGesture { ui.backgroundTapped() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(column.title), \(cards.count) \(cards.count == 1 ? "task" : "tasks")")
    }

    @ViewBuilder
    private func itemView(_ item: Item) -> some View {
        let key = DragController.PanelKey(column: column, priority: item.priority)
        let isTarget = drag.phase == .dragging && drag.target.map { $0.column == column && $0.priority == item.priority && !$0.isOriginalSpot } == true
        switch item.kind {
        case .header(let count, let collapsed):
            PanelHeader(column: column, priority: item.priority, count: count, role: item.role, isTarget: isTarget)
                .opacity(collapsed ? 0.3 : 1)
                .reportsPanelSegment(key, id: item.id, to: drag)
        case .row(let card):
            CardRow(card: card, role: item.role, isTargetPanel: isTarget)
                .reportsPanelSegment(key, id: item.id, to: drag)
        case .insertion:
            InsertionLine(priority: item.priority, role: item.role)
                .reportsPanelSegment(key, id: item.id, to: drag)
        case .placeholder:
            PlaceholderPanel(column: column, priority: item.priority, isTarget: isTarget)
                .reportsPanelSegment(key, id: item.id, to: drag)
        case .spacer:
            Color.clear.frame(height: 8)
        }
    }

    /// The column as panel pieces, with the drag's placeholders and insertion
    /// line woven in.
    static func items(cards: [TaskCard], column: Column, drag: DragController, ui: BoardUI) -> [Item] {
        let dragging = drag.phase == .dragging
        let target = drag.target
        let panels: [Priority] = column == .done ? [.none] : Priority.boardOrder
        var result: [Item] = []

        for priority in panels {
            let group = cards.filter { column == .done || $0.priority == priority }
            let showsLine = dragging && target?.column == column && target?.priority == priority && target?.isOriginalSpot == false
            if group.isEmpty {
                if dragging {
                    if !result.isEmpty { result.append(Item(id: "space-\(priority)", kind: .spacer, priority: priority)) }
                    result.append(Item(id: "placeholder-\(priority)", kind: .placeholder, priority: priority, role: .whole))
                }
                continue
            }

            var panel: [Item] = []
            let anyMatch = !ui.isFiltering || group.contains(where: ui.matches)
            panel.append(Item(id: "header-\(priority)", kind: .header(count: group.count, collapsed: !anyMatch), priority: priority))
            if anyMatch {
                let lineIndex = showsLine ? target?.index ?? -1 : -1
                var otherIndex = 0
                for card in group {
                    let isSource = drag.card?.id == card.id
                    if !isSource {
                        if otherIndex == lineIndex { panel.append(Item(id: "insertion", kind: .insertion, priority: priority)) }
                        otherIndex += 1
                    }
                    panel.append(Item(id: card.id.uuidString, kind: .row(card), priority: priority))
                }
                if lineIndex >= otherIndex { panel.append(Item(id: "insertion", kind: .insertion, priority: priority)) }
            }
            // Corners: the first piece opens the panel, the last closes it.
            for i in panel.indices {
                let first = i == 0, last = i == panel.count - 1
                panel[i].role = first && last ? .whole : (first ? .top : (last ? .bottom : .middle))
            }
            if !result.isEmpty { result.append(Item(id: "space-\(priority)", kind: .spacer, priority: priority)) }
            result += panel
        }
        return result
    }

    private func scroll(to request: BoardUI.ScrollRequest?, with proxy: ScrollViewProxy) {
        guard let request, request.column == column else { return }
        withAnimation(Motion.spring(reduceMotion)) {
            switch request.target {
            case .card(let id): proxy.scrollTo(id.uuidString, anchor: nil)
            case .composer: proxy.scrollTo(ComposerAnchor(column: column), anchor: .bottom)
            }
        }
    }
}

struct ComposerAnchor: Hashable {
    let column: Column
}

private extension View {
    /// Tells the drag controller where this piece of a panel is, so drops can
    /// find the panel under the pointer.
    func reportsPanelSegment(_ key: DragController.PanelKey, id: String, to drag: DragController) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(BoardSpace.viewport)) } action: {
            drag.reportSegment($0, of: key, id: id)
        }
        .onDisappear { drag.forgetSegment(of: key, id: id) }
    }
}

/// Where the dragged card will land: a 2 pt line in the panel's ink.
private struct InsertionLine: View {
    let priority: Priority
    let role: PanelRole

    var body: some View {
        Capsule()
            .fill(Palette.ink(priority))
            .frame(height: 2)
            .padding(.horizontal, 10)
            .frame(height: 6)
            .background(PanelSegment(priority: priority, role: role, isTarget: true))
            .accessibilityHidden(true)
    }
}

/// A priority group that doesn't exist in this column yet, shown while
/// dragging so every priority is a drop target.
private struct PlaceholderPanel: View {
    let column: Column
    let priority: Priority
    let isTarget: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack {
            Text(column == .done ? "COMPLETED" : priority.sectionLabel)
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Palette.ink(priority).opacity(isTarget ? 1 : 0.7))
            Spacer()
        }
        .padding(.horizontal, 13)
        .frame(height: 40)
        .background(shape.fill(Palette.fill(priority).opacity(isTarget ? 1 : 0.55)))
        .overlay(shape.strokeBorder(Palette.ink(priority).opacity(isTarget ? 0.6 : 0.3), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .accessibilityHidden(true)
    }
}

/// An empty column still accepts drops; it says so.
private struct EmptyDropZone: View {
    let column: Column

    private var hint: String {
        switch column {
        case .todo: "Press ⌘N to add a task"
        case .done: "Finished tasks land here"
        default: "Drop tasks here"
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .frame(height: 96)
            .overlay {
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
            }
            .accessibilityLabel("Empty. \(hint).")
    }
}

/// A card plus everything you can do to it: click to select, double-click or
/// Space to edit, drag to move, right-click for the menu, VoiceOver actions.
struct CardRow: View {
    let card: TaskCard
    let role: PanelRole
    let isTargetPanel: Bool

    @Environment(BoardStore.self) private var store
    @Environment(BoardUI.self) private var ui
    @Environment(DragController.self) private var drag
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isDragSource = drag.isActive && drag.card?.id == card.id
        let isSelected = ui.selectedCardID == card.id && !isDragSource

        CardView(
            card: card,
            role: role,
            isSelected: isSelected,
            isDimmed: !ui.matches(card),
            isDragSource: isDragSource,
            isTargetPanel: isTargetPanel,
            today: store.today,
            arrival: ui.arrivals[card.id],
            onCategoryTap: { ui.filter(byCategory: $0) }
        )
        .id(card.id.uuidString)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(BoardSpace.viewport)) } action: {
            drag.reportFrame($0, for: card)
        }
        .onDisappear { drag.forgetFrame(for: card) }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { ui.openEditor(card.id) }
        .simultaneousGesture(TapGesture().onEnded {
            ui.select(card.id)
            ui.focusBoard()
        })
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named(BoardSpace.viewport))
                .onChanged { value in
                    drag.gestureChanged(card: card, start: value.startLocation, location: value.location)
                }
                .onEnded { _ in drag.gestureEnded() }
        )
        .contextMenu { contextMenu }
        .popover(isPresented: editorBinding, arrowEdge: .trailing) {
            CardEditor(cardID: card.id)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityDescription(today: store.today))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { ui.select(card.id) }
        .accessibilityAction(named: "Move to next column") { move(forward: true) }
        .accessibilityAction(named: "Move to previous column") { move(forward: false) }
        .accessibilityAction(named: "Edit") { ui.openEditor(card.id) }
        .accessibilityAction(named: "Delete") { ui.delete(card.id, in: store, animation: Motion.spring(reduceMotion)) }
    }

    private var editorBinding: Binding<Bool> {
        Binding(
            get: { ui.editingCardID == card.id && !drag.isActive },
            set: { isPresented in if !isPresented { ui.editorDidClose(card.id) } }
        )
    }

    private func move(forward: Bool) {
        withAnimation(Motion.spring(reduceMotion)) {
            _ = store.moveToAdjacentColumn(card.id, forward: forward)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Menu("Move to") {
            ForEach(Column.allCases) { column in
                Button(column.title) {
                    withAnimation(Motion.spring(reduceMotion)) { _ = store.moveToTop(card.id, of: column) }
                }
                .disabled(column == card.column)
            }
        }
        Button("Edit") { ui.openEditor(card.id) }
        Button("Duplicate") {
            withAnimation(Motion.spring(reduceMotion)) { _ = store.duplicate(card.id) }
        }
        Menu("Set Priority") {
            ForEach(Priority.boardOrder) { priority in
                Toggle(priority.title, isOn: Binding(
                    get: { card.priority == priority },
                    set: { _ in withAnimation(Motion.spring(reduceMotion)) { store.setPriority(card.id, priority) } }
                ))
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            ui.delete(card.id, in: store, animation: Motion.spring(reduceMotion))
        }
    }
}
