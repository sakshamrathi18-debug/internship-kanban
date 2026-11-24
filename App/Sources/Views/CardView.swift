import KanbanCore
import SwiftUI

/// How a card looks as a row inside its panel. No gestures here; see `CardRow`.
struct CardView: View {
    let card: TaskCard
    let role: PanelRole
    var isSelected = false
    var isDimmed = false
    var isDragSource = false
    var isTargetPanel = false
    var today: CalendarDay
    var onCategoryTap: ((String) -> Void)?

    @State private var fillPriority: Priority
    @State private var pulse: Bool
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(card: TaskCard, role: PanelRole, isSelected: Bool = false, isDimmed: Bool = false, isDragSource: Bool = false,
         isTargetPanel: Bool = false, today: CalendarDay, arrival: BoardUI.Arrival? = nil, onCategoryTap: ((String) -> Void)? = nil) {
        self.onCategoryTap = onCategoryTap
        self.card = card
        self.role = role
        self.isSelected = isSelected
        self.isDimmed = isDimmed
        self.isDragSource = isDragSource
        self.isTargetPanel = isTargetPanel
        self.today = today
        // Coming from another panel: start in its fill and cross-fade over.
        fillPriority = arrival?.previousPriority ?? card.panel
        pulse = arrival?.glow ?? false
    }

    private var panel: Priority { card.panel }
    private var ink: Color { Palette.ink(panel) }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Palette.separator(panel))
                .frame(height: 1)
            CardContent(card: card, today: today, onCategoryTap: onCategoryTap)
                .padding(.top, 9)
                .padding(.horizontal, 13)
                .padding(.bottom, 10)
                .opacity(isDragSource ? 0.3 : 1)
                .background {
                    ZStack {
                        if hovering && !isSelected { Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.03) }
                        if isSelected { ink.opacity(0.10) }
                        ink.opacity(pulse ? 0.12 : 0)
                    }
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: role.hasBottom ? 11 : 0,
                                                      bottomTrailingRadius: role.hasBottom ? 11 : 0, style: .continuous))
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(ink.opacity(0.6), lineWidth: 2)
                            .padding(3)
                    }
                }
        }
        .background(PanelSegment(priority: panel, role: role, fillPriority: fillPriority, isTarget: isTargetPanel))
        .opacity(isDimmed ? 0.3 : 1)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .onAppear(perform: playArrival)
        .onChange(of: panel) { _, newPanel in
            withAnimation(Motion.tint) { fillPriority = newPanel }
        }
    }

    private func playArrival() {
        if fillPriority != panel {
            DispatchQueue.main.async { withAnimation(Motion.tint) { fillPriority = panel } }
        }
        if pulse {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: reduceMotion ? 0.4 : 0.9)) { pulse = false }
            }
        }
    }
}

/// The floating copy that follows the pointer: a standalone card in its
/// panel's fill and border, lifted with a soft shadow.
struct LiftedCardView: View {
    let card: TaskCard
    let today: CalendarDay
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let panel = card.panel
        CardContent(card: card, today: today)
            .padding(.top, 10)
            .padding(.horizontal, 13)
            .padding(.bottom, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.fill(panel))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.border(panel), lineWidth: 1))
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.18), radius: 12, y: 8)
    }
}
