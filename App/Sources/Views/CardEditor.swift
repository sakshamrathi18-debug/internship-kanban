import AppKit
import KanbanCore
import SwiftUI

/// The editor popover. Every change saves live; closing it (Esc or a click
/// outside) ends the session, which ⌘Z then undoes as one step.
struct CardEditor: View {
    let cardID: UUID

    @Environment(BoardStore.self) private var store
    @Environment(BoardUI.self) private var ui
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var titleFocused: Bool

    var body: some View {
        Group {
            if let card = store.card(cardID) {
                form(card)
            } else {
                Text("This task no longer exists.")
                    .foregroundStyle(Palette.textSecondary)
                    .padding(24)
            }
        }
        .frame(width: CardEditor.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.background)
        .onAppear {
            store.beginEditing(cardID)
            titleFocused = true
            // Focusing selects the whole title; put the caret at the end instead.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                for window in NSApp.windows {
                    guard let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
                          editor.selectedRange().length == editor.string.utf16.count else { continue }
                    editor.moveToEndOfDocument(nil)
                }
            }
        }
        .onDisappear {
            store.endEditing()
            ui.editorDidClose(cardID)
        }
    }

    static let width: CGFloat = 400

    private func form(_ card: TaskCard) -> some View {
        let showsWaiting = card.column == .onHold || !card.waitingOn.isEmpty
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Title", text: binding(\.title, in: card), axis: .vertical)
                    .font(.serif(18))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1...6)
                    .focused($titleFocused)
                if card.title.count > TaskCard.maxTitleLength - 30 {
                    Text("\(card.title.count) / \(TaskCard.maxTitleLength)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 2)

            fieldGroup {
                FieldRow("Next step") {
                    TextField("The very next action", text: binding(\.nextStep, in: card), axis: .vertical)
                        .lineLimit(1...3)
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
                        fill: { Palette.fill($0) }, border: { Palette.border($0) }, ink: { Palette.ink($0) },
                        accessibilitySuffix: " priority"
                    )
                }
                FieldRow("Column", divider: true, centered: true) {
                    SegmentedChoice(
                        options: Column.allCases,
                        selection: Binding(
                            get: { store.card(cardID)?.column ?? card.column },
                            set: { value in withAnimation(Motion.spring(reduceMotion)) { store.editColumn(cardID, to: value) } }
                        ),
                        title: \.title,
                        fill: { _ in Palette.background }, border: { _ in Palette.hairline }, ink: { _ in Palette.textPrimary },
                        accessibilitySuffix: " column"
                    )
                }
            }

            fieldGroup {
                FieldRow("Start", centered: true) { DayPill(name: "start", day: binding(\.startDate, in: card)) }
                FieldRow("Due", divider: true, centered: true) { DayPill(name: "due", day: binding(\.dueDate, in: card)) }
                if card.dueBeforeStart {
                    Text("Due date is before the start date")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.overdue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 12 + FieldRow<EmptyView>.labelWidth + 10)
                        .padding(.bottom, 9)
                }
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 12.5))
        .padding(16)
        .disabled(store.isReadOnly)
    }

    /// Grouped rows on the `Field` background.
    private func fieldGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.field))
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<TaskCard, Value>, in card: TaskCard) -> Binding<Value> {
        Binding(
            get: { (store.card(cardID) ?? card)[keyPath: keyPath] },
            set: { newValue in
                store.edit(cardID) { $0[keyPath: keyPath] = newValue }
            }
        )
    }
}
