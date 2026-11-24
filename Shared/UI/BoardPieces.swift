import KanbanCore
import SwiftUI

// Board pieces shared by the Mac and iPhone apps.

/// Text and control sizes are drawn for the Mac; the iPhone scales them up
/// (≈ 1.18) so a 13 pt title reads like iOS body text.
private struct BoardScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var boardScale: CGFloat {
        get { self[BoardScaleKey.self] }
        set { self[BoardScaleKey.self] = newValue }
    }
}

/// Where a piece sits within its priority panel. Rows, headers and the
/// insertion line each draw their own slice of the panel (fill + border), so
/// the column can stay a flat lazy stack even with hundreds of cards.
enum PanelRole: Equatable {
    case top, middle, bottom, whole

    var hasTop: Bool { self == .top || self == .whole }
    var hasBottom: Bool { self == .bottom || self == .whole }
}

/// One slice of a priority panel: 12 pt continuous corners where it starts or
/// ends, a 1 pt border on the outside edges only, and no shadow.
struct PanelSegment: View {
    let priority: Priority
    let role: PanelRole
    var fillPriority: Priority?
    var isTarget = false

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: role.hasTop ? 12 : 0,
            bottomLeadingRadius: role.hasBottom ? 12 : 0,
            bottomTrailingRadius: role.hasBottom ? 12 : 0,
            topTrailingRadius: role.hasTop ? 12 : 0,
            style: .continuous
        )
        shape
            .fill(Palette.fill(fillPriority ?? priority))
            .overlay {
                // Extend past open edges and clip, so only the outer edges show.
                UnevenRoundedRectangle(
                    topLeadingRadius: role.hasTop ? 12 : 0,
                    bottomLeadingRadius: role.hasBottom ? 12 : 0,
                    bottomTrailingRadius: role.hasBottom ? 12 : 0,
                    topTrailingRadius: role.hasTop ? 12 : 0,
                    style: .continuous
                )
                .strokeBorder(isTarget ? Palette.ink(priority).opacity(0.5) : Palette.border(priority), lineWidth: 1)
                .padding(.top, role.hasTop ? 0 : -2)
                .padding(.bottom, role.hasBottom ? 0 : -2)
                .clipShape(Rectangle())
            }
    }
}

/// A row's text: title, next step, "Waiting on", and the meta line.
struct CardContent: View {
    let card: TaskCard
    let today: CalendarDay
    var onCategoryTap: ((String) -> Void)?
    @Environment(\.boardScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            Text(card.title)
                .font(.system(size: 13 * scale, weight: .semibold))
                .tracking(-0.08)
                .lineSpacing(2)
                .foregroundStyle(card.isDone ? Palette.textSecondary : Palette.textPrimary)
                .lineLimit(3)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if !card.nextStep.isEmpty {
                Text(card.nextStep)
                    .font(.system(size: 11.5 * scale))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }

            if !card.waitingOn.isEmpty && card.column == .onHold {
                (Text("Waiting on ").foregroundStyle(Palette.textSecondary)
                    + Text(card.waitingOn).fontWeight(.medium).foregroundStyle(Palette.textPrimary))
                    .font(.system(size: 11.5 * scale))
                    .lineLimit(1)
            }

            if hasMeta { meta }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dateLabel: DateLabel? { DateLabels.labels(for: card, today: today).last }
    private var hasMeta: Bool { !card.category.isEmpty || dateLabel != nil }

    private var meta: some View {
        HStack(spacing: 8) {
            if !card.category.isEmpty {
                Text(card.category)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .layoutPriority(0)
                    .contentShape(Rectangle())
                    .onTapGesture { onCategoryTap?(card.category) }
                    .help(onCategoryTap == nil ? "" : "Show only “\(card.category)”")
            }
            Spacer(minLength: 0)
            if let label = dateLabel {
                Text(label.text)
                    .fontWeight(label.isOverdue || label.text == "Today" ? .semibold : .medium)
                    .foregroundStyle(label.isOverdue ? Palette.overdue : (label.text == "Today" ? Palette.textPrimary : Palette.textTertiary))
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
            }
        }
        .font(.system(size: 10.5 * scale))
        .padding(.top, 3 * scale)
    }
}

/// "HIGH 2": the panel's label in its ink, then the count.
struct PanelHeader: View {
    let column: Column
    let priority: Priority
    let count: Int
    let role: PanelRole
    var isTarget = false
    /// Overrides the section label (the archive says "ARCHIVED").
    var label: String?
    @Environment(\.boardScale) private var scale

    var body: some View {
        HStack(spacing: 7) {
            #if os(iOS)
            // White cards on iPhone: a dot in the priority's system colour.
            Circle()
                .fill(Palette.accent(column == .done ? .none : priority))
                .frame(width: 8 * scale, height: 8 * scale)
            #endif
            Text(label ?? (column == .done ? "COMPLETED" : priority.sectionLabel))
                .font(.system(size: 10.5 * scale, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Palette.ink(priority))
            Text("\(count)")
                .font(.system(size: 10.5 * scale, weight: .medium).monospacedDigit())
                .foregroundStyle(Palette.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.top, 9 * scale)
        .padding(.horizontal, 13 * scale)
        .padding(.bottom, 8 * scale)
        .background(PanelSegment(priority: priority, role: role, isTarget: isTarget))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension TaskCard {
    /// The panel a card sits in: its priority, except Done, which is one group.
    var panel: Priority { column == .done ? .none : priority }


    /// "Post infographic on LinkedIn, Medium priority, To Do, no due date".
    func accessibilityDescription(today: CalendarDay) -> String {
        var parts = [title]
        parts.append(priority == .none ? "no priority" : "\(priority.title) priority")
        parts.append(column.title)
        if let due = dueDate {
            parts.append(DateLabels.due(due, today: today).spoken)
        } else {
            parts.append("no due date")
        }
        if let start = startDate, let label = DateLabels.starts(start, today: today) {
            parts.append(label.spoken)
        }
        if !category.isEmpty { parts.append("category \(category)") }
        if !nextStep.isEmpty { parts.append("next step: \(nextStep)") }
        if !waitingOn.isEmpty { parts.append("waiting on \(waitingOn)") }
        return parts.joined(separator: ", ")
    }
}
