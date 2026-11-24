import KanbanCore
import SwiftUI

/// Done cards that aged out of the board. Search, and restore to To Do.
struct PhoneArchive: View {
    @Environment(BoardStore.self) private var store
    @Environment(PhoneUI.self) private var ui
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Done cards move here \(store.settings.archiveAfterDays) days after they're finished.")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textTertiary)

                    if cards.isEmpty {
                        VStack(spacing: 6) {
                            Text(store.archived.isEmpty ? "Nothing archived yet" : "No matches")
                                .font(.serif(19))
                                .foregroundStyle(Palette.textSecondary)
                            Text(store.archived.isEmpty ? "Finished tasks will collect here." : "Try a different search.")
                                .font(.system(size: 14))
                                .foregroundStyle(Palette.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        panel
                    }
                }
                .padding(PhoneMetrics.gutter)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Archive")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search archive")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .tint(Palette.appAccent)
        .presentationBackground(Palette.background)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            PanelHeader(column: .done, priority: .none, count: cards.count, role: .top, label: "ARCHIVED")
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                VStack(spacing: 0) {
                    Rectangle().fill(Palette.separator(.none)).frame(height: 1)
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(2)
                            Text(detail(for: card))
                                .font(.system(size: 12.5))
                                .foregroundStyle(Palette.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Button("Restore") {
                            withAnimation(Motion.spring(reduceMotion)) { _ = store.restoreFromArchive(card.id) }
                            ui.column = .todo
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Capsule().fill(Palette.field))
                        .buttonStyle(.plain)
                        .disabled(store.isReadOnly)
                        .accessibilityLabel("Restore \(card.title) to To Do")
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                }
                .background(PanelSegment(priority: .none, role: index == cards.count - 1 ? .bottom : .middle))
            }
        }
    }

    private func detail(for card: TaskCard) -> String {
        var parts: [String] = []
        if let completed = card.completedAt {
            parts.append("Finished \(completed.formatted(.dateTime.day().month(.abbreviated)))")
        }
        if !card.category.isEmpty { parts.append(card.category) }
        if card.priority != .none { parts.append(card.priority.title) }
        return parts.joined(separator: " · ")
    }
}
