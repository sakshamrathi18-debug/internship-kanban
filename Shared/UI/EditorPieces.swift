import KanbanCore
import SwiftUI

// Editor building blocks shared by the Mac popover and the iPhone sheet.

struct FieldRow<Content: View>: View {
    static var labelWidth: CGFloat { 62 }
    #if os(iOS)
    // An empty vertical text field on iOS reports its baseline below the placeholder.
    static var textAlignment: VerticalAlignment { .top }
    #else
    static var textAlignment: VerticalAlignment { .firstTextBaseline }
    #endif
    @Environment(\.boardScale) private var scale

    let label: String
    let divider: Bool
    let centered: Bool
    @ViewBuilder let content: Content

    init(_ label: String, divider: Bool = false, centered: Bool = false, @ViewBuilder content: () -> Content) {
        self.label = label
        self.divider = divider
        self.centered = centered
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if divider {
                Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 12)
            }
            HStack(alignment: centered ? .center : Self.textAlignment, spacing: 10) {
                Text(label)
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .frame(width: Self.labelWidth * scale, alignment: .leading)
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, (centered ? 6 : 9) * scale)
        }
    }
}

/// An evenly divided segmented control drawn in board colours. For priority
/// the selected segment wears that priority's panel colours, so picking a
/// priority previews its section.
struct SegmentedChoice<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: KeyPath<Option, String>
    let fill: (Option) -> Color
    let border: (Option) -> Color
    let ink: (Option) -> Color
    let accessibilitySuffix: String
    @Environment(\.boardScale) private var scale

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(option[keyPath: title])
                        .font(.system(size: 11.5 * scale, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? ink(option) : Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24 * scale)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(fill(option))
                                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(border(option), lineWidth: 1))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option[keyPath: title] + accessibilitySuffix)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }
}

/// Free text with one-click suggestions from categories already in use.
struct CategoryField: View {
    @Binding var text: String
    let categories: [String]
    @Environment(\.boardScale) private var scale

    private var suggestions: [String] {
        let query = text.trimmingCharacters(in: .whitespaces)
        return categories
            .filter { $0.caseInsensitiveCompare(query) != .orderedSame }
            .filter { query.isEmpty || $0.localizedStandardContains(query) }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("e.g. Brochure", text: $text)
            if !suggestions.isEmpty {
                FlowRow(spacing: 5) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { text = suggestion }
                            .buttonStyle(.plain)
                            .font(.system(size: 11 * scale))
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.horizontal, 7 * scale)
                            .padding(.vertical, 2 * scale)
                            .background(Capsule().fill(Palette.background))
                            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                    }
                }
            }
        }
    }
}

/// A date as a pill ("14 Oct 2026") that opens a calendar, with a clear (×)
/// button; "Add date" when there isn't one.
struct DayPill: View {
    let name: String
    @Binding var day: CalendarDay?
    @State private var picking = false
    @Environment(\.boardScale) private var scale

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if day == nil { day = CalendarDay.today() }
                picking = true
            } label: {
                Text(day.map { $0.date().formatted(.dateTime.day().month(.abbreviated).year()) } ?? "Add \(name) date")
                    .font(.system(size: 12 * scale, weight: day == nil ? .regular : .medium))
                    .foregroundStyle(day == nil ? Palette.textTertiary : Palette.textPrimary)
                    .padding(.horizontal, 10 * scale)
                    .frame(height: 24 * scale)
                    .background(Capsule().fill(Palette.background))
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                DatePicker(name.capitalized, selection: Binding(
                    get: { (day ?? CalendarDay.today()).date() },
                    set: { day = CalendarDay($0) }
                ), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(10)
                .frame(minWidth: 300)
                .presentationCompactAdaptation(.popover)
            }
            if day != nil {
                Button {
                    day = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear the \(name) date")
                .accessibilityLabel("Clear \(name) date")
            }
        }
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // With no width offered, assume a modest one rather than a single endless row.
        let width = proposal.width.map { $0.isFinite ? $0 : 260 } ?? 260
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
