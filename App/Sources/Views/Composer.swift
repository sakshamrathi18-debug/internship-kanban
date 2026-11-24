import KanbanCore
import SwiftUI

/// "+ Add task" at the bottom of a column, which turns into the composer.
struct ComposerSlot: View {
    let column: Column
    @Environment(BoardUI.self) private var ui
    @State private var hovering = false

    var body: some View {
        if ui.composerColumn == column {
            Composer(column: column)
        } else {
            Button {
                ui.openComposer(column)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                    Text("Add task")
                        .font(.system(size: 12.5))
                    Spacer()
                }
                .foregroundStyle(hovering ? Palette.textSecondary : Palette.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .accessibilityLabel("Add task to \(column.title)")
        }
    }
}

/// The inline composer. Enter adds and stays open for the next one;
/// Shift+Enter adds and opens the editor; Esc closes (discarding the text);
/// clicking elsewhere keeps what was typed.
struct Composer: View {
    let column: Column

    @Environment(BoardStore.self) private var store
    @Environment(BoardUI.self) private var ui
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text = ""
    @State private var pastedLines: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ComposerField(
                text: $text,
                placeholder: "Task title",
                focusRequest: ui.composerFocusRequest,
                onSubmit: submit,
                onCancel: cancel,
                onFocusLost: focusLost,
                onMultilinePaste: { pastedLines = $0 }
            )

            if !pastedLines.isEmpty {
                HStack(spacing: 8) {
                    Text("Create \(pastedLines.count) tasks?")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 0)
                    Button("Keep as one") { keepAsOne() }
                        .controlSize(.small)
                    Button("Create \(pastedLines.count)") { createAll() }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                }
                .transition(.opacity)
            } else {
                Text("↩ add · ⇧↩ add and edit · esc close")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.fill(.none))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.textTertiary.opacity(0.45), lineWidth: 1)
        )
        .animation(Motion.hover, value: pastedLines)
    }

    private var animation: Animation { Motion.spring(reduceMotion) }

    private func submit(openEditor: Bool) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return } // stay open, no fuss
        let raw = text
        text = ""
        let card = withAnimation(animation) { store.addCard(raw, to: column) }
        if openEditor, let card {
            ui.closeComposer(column)
            ui.openEditor(card.id)
        }
    }

    private func cancel() {
        text = ""
        pastedLines = []
        ui.closeComposer(column)
        ui.focusBoard()
    }

    /// Focus went elsewhere: better to keep the words than lose them.
    private func focusLost() {
        let raw = text
        text = ""
        if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            withAnimation(animation) { _ = store.addCard(raw, to: column) }
        }
        if pastedLines.isEmpty { ui.closeComposer(column) }
    }

    private func createAll() {
        let lines = pastedLines
        pastedLines = []
        withAnimation(animation) { _ = store.addCards(lines, to: column) }
        ui.composerFocusRequest += 1
    }

    private func keepAsOne() {
        let joined = ([text] + pastedLines).filter { !$0.isEmpty }.joined(separator: " ")
        text = String(joined.prefix(TaskCard.maxTitleLength))
        pastedLines = []
        ui.composerFocusRequest += 1
    }
}
