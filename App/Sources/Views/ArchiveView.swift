import KanbanCore
import SwiftUI

/// Done cards that aged out of the board, shown like a Done panel.
/// Search, and restore to To Do.
struct ArchiveView: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""

    private var cards: [TaskCard] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.archived }
        return store.archived.filter {
            $0.title.localizedStandardContains(query) || $0.category.localizedStandardContains(query)
                || $0.nextStep.localizedStandardContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Archive")
                        .font(.serif(20))
                        .foregroundStyle(Palette.textPrimary)
                    Text("Done cards move here \(store.settings.archiveAfterDays) days after they're finished.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                    TextField("Search archive", text: $query).textFieldStyle(.plain).font(.system(size: 12.5))
                }
                .padding(.horizontal, 9)
                .frame(width: 190, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.field))
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Rectangle().fill(Palette.hairline).frame(height: 1)

            if cards.isEmpty {
                VStack(spacing: 6) {
                    Text(store.archived.isEmpty ? "Nothing archived yet" : "No matches")
                        .font(.serif(16))
                        .foregroundStyle(Palette.textSecondary)
                    Text(store.archived.isEmpty ? "Finished tasks will collect here." : "Try a different search.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        HStack(spacing: 7) {
                            Text("ARCHIVED")
                                .font(.system(size: 10.5, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(Palette.ink(.none))
                            Text("\(cards.count)")
                                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(Palette.textTertiary)
                            Spacer()
                        }
                        .padding(.top, 9)
                        .padding(.horizontal, 13)
                        .padding(.bottom, 8)
                        ForEach(cards) { card in
                            Rectangle().fill(Palette.separator(.none)).frame(height: 1)
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(card.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Palette.textSecondary)
                                        .lineLimit(2)
                                    Text(detail(for: card))
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(Palette.textTertiary)
                                }
                                Spacer()
                                Button("Restore to To Do") {
                                    withAnimation(Motion.spring(reduceMotion)) { _ = store.restoreFromArchive(card.id) }
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.textSecondary)
                                .disabled(store.isReadOnly)
                            }
                            .padding(.top, 9)
                            .padding(.horizontal, 13)
                            .padding(.bottom, 10)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.fill(.none))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.border(.none), lineWidth: 1))
                    )
                    .padding(20)
                }
            }
        }
        .background(Palette.background)
        .frame(minWidth: 560, idealWidth: 600, minHeight: 420, idealHeight: 520)
    }

    private func detail(for card: TaskCard) -> String {
        var parts: [String] = []
        if let completed = card.completedAt {
            parts.append("Finished \(completed.formatted(.dateTime.day().month(.abbreviated).year()))")
        }
        if !card.category.isEmpty { parts.append(card.category) }
        if card.priority != .none { parts.append("\(card.priority.title) priority") }
        return parts.joined(separator: " · ")
    }
}
