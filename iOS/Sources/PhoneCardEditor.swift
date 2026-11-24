import KanbanCore
import SwiftUI

/// The editor as a sheet, with the same field groups as the Mac popover.
/// Every change saves live; closing the sheet ends the session, so Undo
/// reverts the whole edit in one step.
struct PhoneCardEditor: View {
    let cardID: UUID

    @Environment(BoardStore.self) private var store
    @Environment(PhoneUI.self) private var ui
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let card = store.card(cardID) {
                    ScrollView { form(card) }
                        .scrollDismissesKeyboard(.interactively)
                } else {
                    Text("This task no longer exists.")
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Palette.background)
        .tint(Palette.appAccent)
        .onAppear {
            store.beginEditing(cardID)
            // New cards (empty-ish titles) get the keyboard straight away.
            if store.card(cardID)?.title.isEmpty ?? false { titleFocused = true }
        }
        .onDisappear { store.endEditing() }
    }

    private func form(_ card: TaskCard) -> some View {
        let showsWaiting = card.column == .onHold || !card.waitingOn.isEmpty
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Title", text: binding(\.title, in: card), axis: .vertical)
                    .font(.serif(24))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1...6)
                    .focused($titleFocused)
                if card.title.count > TaskCard.maxTitleLength - 30 {
                    Text("\(card.title.count) / \(TaskCard.maxTitleLength)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 4)

            fieldGroup {
                FieldRow("Next step") {
                    TextField("The very next action", text: binding(\.nextStep, in: card), axis: .vertical)
                        .lineLimit(1...4)
                }
                if showsWaiting {
                    FieldRow("Waiting on", divider: true) {
                        TextField("Who or what", text: binding(\.waitingOn, in: card))
                    }
                }
                FieldRow("Category", divider: true) {
                    CategoryField(text: binding(\.category, in: card), categories: store.categories)
                }
            }

            fieldGroup {
                FieldRow("Priority", centered: true) {
                    SegmentedChoice(
                        options: Priority.editorOrder,
                        selection: Binding(
                            get: { store.card(cardID)?.priority ?? card.priority },
                            set: { value in withAnimation(Motion.spring(reduceMotion)) { store.edit(cardID) { $0.priority = value } } }
                        ),
                        title: \.title,
                        fill: { Palette.accent($0).opacity(0.16) }, border: { Palette.accent($0).opacity(0.35) }, ink: { Palette.ink($0) },
                        accessibilitySuffix: " priority"
                    )
                }
                FieldRow("Column", divider: true, centered: true) {
                    SegmentedChoice(
                        options: Column.allCases,
                        selection: Binding(
                            get: { store.card(cardID)?.column ?? card.column },
                            set: { value in
                                withAnimation(Motion.spring(reduceMotion)) { store.editColumn(cardID, to: value) }
                                ui.column = value
                            }
                        ),
                        title: \.shortTitle,
                        fill: { _ in Palette.field }, border: { _ in Palette.hairline }, ink: { _ in Palette.textPrimary },
                        accessibilitySuffix: " column"
                    )
                }
            }

            fieldGroup {
                FieldRow("Start", centered: true) { DayPill(name: "start", day: binding(\.startDate, in: card)) }
                FieldRow("Due", divider: true, centered: true) { DayPill(name: "due", day: binding(\.dueDate, in: card)) }
                if card.dueBeforeStart {
                    Text("Due date is before the start date")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.overdue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 12 + FieldRow<EmptyView>.labelWidth * PhoneMetrics.scale + 10)
                        .padding(.bottom, 10)
                }
            }

            Button(role: .destructive) {
                dismiss()
                let id = cardID
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    ui.delete(id, in: store, animation: Motion.spring(reduceMotion))
                }
            } label: {
                Text("Delete Task")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.overdue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.fill(.none)))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .textFieldStyle(.plain)
        .font(.system(size: 12.5 * PhoneMetrics.scale))
        .padding(PhoneMetrics.gutter)
        .disabled(store.isReadOnly)
    }

    private func fieldGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.fill(.none)))
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<TaskCard, Value>, in card: TaskCard) -> Binding<Value> {
        Binding(
            get: { (store.card(cardID) ?? card)[keyPath: keyPath] },
            set: { newValue in store.edit(cardID) { $0[keyPath: keyPath] = newValue } }
        )
    }
}

extension Column {
    /// Fits four segments across a phone.
    var shortTitle: String {
        switch self {
        case .todo: "To Do"
        case .inProgress: "Doing"
        case .onHold: "On Hold"
        case .done: "Done"
        }
    }
}
