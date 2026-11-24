import KanbanCore
import SwiftUI

/// The column's serif title and count, then a hairline rule. Columns carry no
/// colour; In Progress warns in amber text when over the WIP limit.
struct ColumnHeader: View {
    let column: Column
    let count: Int

    @Environment(BoardStore.self) private var store

    private var limit: Int? { column == .inProgress ? store.settings.wipLimit : nil }
    private var overWIP: Bool { column == .inProgress && store.isOverWIPLimit }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(column.title)
                    .font(.serif(20))
                    .tracking(-0.2)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(countText)
                    .font(.system(size: 12.5, weight: overWIP ? .semibold : .medium).monospacedDigit())
                    .foregroundStyle(overWIP ? Palette.wipWarning : Palette.textTertiary)
                    .contentTransition(.numericText())
                    .animation(Motion.hover, value: count)
                Spacer(minLength: 4)
                if overWIP {
                    Text("over limit")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.wipWarning)
                } else if column == .done {
                    Text("\(store.stats.doneThisWeek) this week")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 13)

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .help(tooltip)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(column.title), \(count)")
        .accessibilityHint(tooltip)
    }

    private var countText: String {
        if let limit { return "\(count) of \(limit)" }
        return "\(count)"
    }

    /// The column's policy, kept obvious.
    private var tooltip: String {
        switch column {
        case .todo:
            return column.meaning
        case .inProgress:
            if overWIP, let limit { return "\(count) / \(limit) in progress: finish one before starting another?" }
            if let limit { return "\(column.meaning) · aim for \(limit) at most" }
            return column.meaning
        case .onHold:
            return "\(column.meaning) · note what each card is waiting on"
        case .done:
            return "\(column.meaning) · cards move to the Archive after \(store.settings.archiveAfterDays) days"
        }
    }
}
