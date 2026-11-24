import KanbanCore
import SwiftUI
import WidgetKit

// The widget's views. They live in Shared so the app's debug renderer can draw
// them too. `MoveForwardButton` and `CardLink` are defined separately in each
// target: the real App Intent button and `Link` in the widget, look-alikes in
// the app (which can't render either into an image).

/// Whether the widget is drawn in full colour (vs. the desktop's dimmed
/// "accented"/monochrome style). Passed in because `widgetRenderingMode` can't
/// be set from outside a widget.
private struct FullColorKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var kanbanFullColor: Bool {
        get { self[FullColorKey.self] }
        set { self[FullColorKey.self] = newValue }
    }
}

enum WidgetText {
    static let appName = "Kanban Board"
}

struct BoardWidgetContent: View {
    let entry: BoardEntry
    let family: WidgetFamily

    var body: some View {
        Group {
            switch entry.content {
            case .noData:
                EmptyStateView(message: "Open \(WidgetText.appName) to add your first task")
                    .widgetURL(DeepLink.board)
            case .board(let board):
                switch family {
                case .systemSmall: SmallBoardView(board: board, now: entry.date)
                case .systemLarge: LargeBoardView(board: board, today: entry.today, now: entry.date)
                default: MediumBoardView(board: board, today: entry.today)
                }
            }
        }
        .padding(family == .systemMedium ? 13 : 15)
    }
}

private extension Board {
    var openCount: Int { cards(in: .todo).count + cards(in: .inProgress).count + cards(in: .onHold).count }
    var isAllClear: Bool { openCount == 0 && !cards(in: .done).isEmpty }
    var hasNoActiveCards: Bool { activeCards.isEmpty }
}

// MARK: - Small

/// The In Progress count, big and serif, "of 3"; To Do · On Hold · Done below.
private struct SmallBoardView: View {
    let board: Board
    let now: Date

    var body: some View {
        let stats = BoardStats(cards: board.activeCards, now: now)
        let limit = board.settings.wipLimit
        let over = BoardStats.isOverWIP(inProgress: stats.inProgress, limit: limit)
        VStack(alignment: .leading, spacing: 0) {
            Text(board.isAllClear ? "Done" : "In Progress")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
            Spacer(minLength: 0)
            if board.isAllClear {
                Text("All clear ✓")
                    .font(.serif(24))
                    .foregroundStyle(Palette.textPrimary)
                    .widgetAccentable()
            } else if board.hasNoActiveCards {
                Text("No tasks yet")
                    .font(.serif(20))
                    .foregroundStyle(Palette.textPrimary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(stats.inProgress)")
                        .font(.serif(48))
                        .foregroundStyle(Palette.textPrimary)
                        .widgetAccentable()
                        .contentTransition(.numericText())
                    if let limit {
                        Text("of \(limit)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(over ? Palette.wipWarning : Palette.textTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                mini("To Do", stats.todo)
                Spacer(minLength: 2)
                mini("On Hold", stats.onHold)
                Spacer(minLength: 2)
                mini("Done", stats.done)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(DeepLink.board)
        .accessibilityElement(children: .combine)
    }

    private func mini(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
    }
}

// MARK: - Medium

/// "Now": up to 3 In Progress cards, then To Do to fill 4 rows.
/// With nothing in progress, the header reads "Up next".
private struct MediumBoardView: View {
    let board: Board
    let today: CalendarDay

    var body: some View {
        let inProgress = board.cards(in: .inProgress)
        let todo = board.cards(in: .todo)
        let onHold = board.cards(in: .onHold)
        let rows: [TaskCard] = {
            let now = Array(inProgress.prefix(3))
            let combined = now + todo.prefix(4 - now.count)
            return combined.isEmpty ? Array(onHold.prefix(4)) : combined
        }()
        let header = !inProgress.isEmpty ? "Now" : (!todo.isEmpty ? "Up next" : "On hold")

        if board.isAllClear {
            EmptyStateView(message: "All clear ✓", detail: "\(board.cards(in: .done).count) done")
        } else if rows.isEmpty {
            EmptyStateView(message: "No tasks yet. Add one in \(WidgetText.appName).")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(header)
                        .font(.serif(14, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: 4)
                    Text("\(inProgress.count) in progress · \(todo.count) to do")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
                ForEach(rows) { card in
                    WidgetCardRow(card: card, today: today)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Large

/// Plain counts per column, then the cards as priority-coloured rows (Now,
/// Up next, On hold) with "+N more", and a "this week" bar at the bottom.
private struct LargeBoardView: View {
    let board: Board
    let today: CalendarDay
    let now: Date

    struct Section: Identifiable {
        let column: Column
        let cards: [TaskCard]
        let total: Int
        var id: Column { column }
    }

    private var sections: [Section] {
        let columns: [Column] = [.inProgress, .todo, .onHold]
        let lists = columns.map { board.cards(in: $0) }
        let headers = lists.filter { !$0.isEmpty }.count + (lists[0].isEmpty ? 1 : 0) // + "Nothing in progress"
        var remaining = headers <= 1 ? 6 : 5
        var shown = lists.map { $0.isEmpty ? 0 : 1 }
        remaining -= shown.reduce(0, +)
        for i in lists.indices where remaining > 0 {
            let extra = min(lists[i].count - shown[i], remaining)
            shown[i] += extra
            remaining -= extra
        }
        return columns.indices.compactMap { i in
            lists[i].isEmpty ? nil : Section(column: columns[i], cards: Array(lists[i].prefix(shown[i])), total: lists[i].count)
        }
    }

    var body: some View {
        if board.hasNoActiveCards {
            EmptyStateView(message: "No tasks yet. Add one in \(WidgetText.appName).")
        } else {
            let nothingInProgress = board.cards(in: .inProgress).isEmpty
            let firstTodo = board.cards(in: .todo).first?.id
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 0) {
                    ForEach(Column.allCases) { column in
                        count(column)
                        if column != .done { Spacer(minLength: 4) }
                    }
                }
                Rectangle().fill(Palette.hairline).frame(height: 1)

                if board.isAllClear {
                    EmptyStateView(message: "All clear ✓", detail: "Nothing left to do")
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        if nothingInProgress {
                            Text("Nothing in progress")
                                .font(.serif(13))
                                .foregroundStyle(Palette.textSecondary)
                                .padding(.horizontal, 2)
                        }
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 4) {
                                SectionHeader(column: section.column, total: section.total, hidden: section.total - section.cards.count)
                                ForEach(section.cards) { card in
                                    WidgetCardRow(card: card, today: today, startLabel: nothingInProgress && card.id == firstTodo)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                WeekBar(board: board, now: now)
            }
        }
    }

    private func count(_ column: Column) -> some View {
        let value = board.cards(in: column).count
        let over = column == .inProgress && BoardStats.isOverWIP(inProgress: value, limit: board.settings.wipLimit)
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(.serif(20))
                .foregroundStyle(over ? Palette.wipWarning : Palette.textPrimary)
                .monospacedDigit()
            Text(column.title)
                .font(.system(size: 10))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SectionHeader: View {
    let column: Column
    let total: Int
    let hidden: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.serif(13, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
            Text("\(total)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Palette.textTertiary)
            Spacer(minLength: 4)
            if hidden > 0 {
                Text("+\(hidden) more")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.horizontal, 2)
    }

    private var title: String {
        switch column {
        case .inProgress: "Now"
        case .todo: "Up next"
        case .onHold: "On hold"
        case .done: "Done"
        }
    }
}

/// "This week · 1 of 3 done": finished this week, out of those plus what's open.
private struct WeekBar: View {
    let board: Board
    let now: Date

    var body: some View {
        let done = BoardStats(cards: Array(board.cardsByID.values), now: now).doneThisWeek
        let total = done + board.openCount
        let fraction = total == 0 ? 0 : Double(done) / Double(total)
        VStack(alignment: .leading, spacing: 5) {
            (Text("This week · ").foregroundStyle(Palette.textTertiary)
                + Text("\(done) of \(total)").fontWeight(.semibold).foregroundStyle(Palette.textPrimary)
                + Text(" done").foregroundStyle(Palette.textTertiary))
                .font(.system(size: 11))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.hairline)
                    Capsule()
                        .fill(Palette.textPrimary)
                        .frame(width: max(fraction > 0 ? 3 : 0, geometry.size.width * fraction))
                        .widgetAccentable()
                }
            }
            .frame(height: 3)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Shared pieces

/// A 28 pt row in its priority's fill: H/M/L letter · title · date · → button.
/// The row opens the app with the card selected; the button moves it forward.
struct WidgetCardRow: View {
    let card: TaskCard
    let today: CalendarDay
    var startLabel = false
    @Environment(\.kanbanFullColor) private var fullColor

    var body: some View {
        HStack(spacing: 7) {
            CardLink(card: card) {
                HStack(spacing: 7) {
                    Text(card.priority.letter)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(fullColor ? Palette.ink(card.priority) : Color.primary)
                        .frame(width: 9, alignment: .leading)
                        .widgetAccentable()
                    Text(card.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    if let label = DateLabels.labels(for: card, today: today).last {
                        Text(label.text)
                            .font(.system(size: 10.5, weight: label.isOverdue || label.text == "Today" ? .semibold : .medium))
                            .foregroundStyle(label.isOverdue ? Palette.overdue : (label.text == "Today" ? Palette.textPrimary : Palette.textTertiary))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            MoveForwardButton(card: card, startLabel: startLabel)
        }
        .padding(.leading, 9)
        .padding(.trailing, 3)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(fullColor ? Palette.fill(card.priority) : Color.white.opacity(0.09))
        )
        .overlay {
            if fullColor {
                RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Palette.border(card.priority), lineWidth: 1)
            }
        }
    }
}

/// The look of the "→" button: a 22 pt circle in ink @ 15%, or a "Start →"
/// capsule (shared; each target wraps it its own way).
struct MoveForwardGlyph: View {
    let card: TaskCard
    var startLabel = false
    @Environment(\.kanbanFullColor) private var fullColor

    var body: some View {
        let ink = fullColor ? Palette.ink(card.priority) : Color.primary
        Group {
            if startLabel {
                HStack(spacing: 3) {
                    Text("Start")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 10.5, weight: .bold))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(ink.opacity(0.15)))
            } else {
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(ink.opacity(0.15)))
            }
        }
        .foregroundStyle(ink)
        .contentShape(Rectangle())
    }
}

struct EmptyStateView: View {
    let message: String
    var detail: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(message)
                .font(.serif(16))
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
