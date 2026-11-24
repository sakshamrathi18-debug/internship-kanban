import KanbanCore
import SwiftUI

/// "+ New Task": a short sheet with one field. Return adds the task and keeps
/// the field open for the next. Quick syntax works as on the Mac.
struct PhoneComposer: View {
    @State var column: Column

    @Environment(BoardStore.self) private var store
    @Environment(PhoneUI.self) private var ui
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var text = ""
    @State private var added = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("New Task")
                    .font(.serif(22, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.appAccent)
            }

            HStack(spacing: 10) {
                TextField("Task title", text: $text, axis: .vertical)
                    .font(.system(size: 17))
                    .lineLimit(1...3)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(submit)
                    .onChange(of: text) { _, value in
                        // A return key in a vertical field arrives as a newline.
                        if value.contains("\n") {
                            text = value.replacingOccurrences(of: "\n", with: "")
                            submit()
                        }
                    }
                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.buttonPrimaryText)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Palette.buttonPrimary))
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.35 : 1)
                .accessibilityLabel("Add task")
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.fill(.none)))

            HStack(spacing: 8) {
                Text("Add to")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textTertiary)
                SegmentedChoice(
                    options: Column.allCases,
                    selection: $column,
                    title: \.shortTitle,
                    fill: { _ in Palette.fill(.none) }, border: { _ in Palette.hairline }, ink: { _ in Palette.textPrimary },
                    accessibilitySuffix: " column"
                )
            }

            Text(added > 0 ? "Added \(added) to \(column.title). Keep typing to add another."
                           : "Tip: add !high, #Category or due:fri to the title.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(PhoneMetrics.gutter)
        .padding(.top, 6)
        .background(Palette.background.ignoresSafeArea())
        .presentationDetents([.height(250)])
        .presentationBackground(Palette.background)
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
    }

    private func submit() {
        guard let card = withAnimation(Motion.spring(reduceMotion), { store.addCard(text, to: column) }) else { return }
        ui.justAdded.insert(card.id)
        ui.column = column
        text = ""
        added += 1
        focused = true
    }
}
