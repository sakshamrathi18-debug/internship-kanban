import AppIntents
import KanbanCore
import SwiftUI
import WidgetKit

@main
struct KanbanWidgetBundle: WidgetBundle {
    var body: some Widget {
        BoardWidget()
    }
}

struct BoardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.board, provider: BoardProvider()) { entry in
            BoardWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) { Palette.widgetBackground }
        }
        .configurationDisplayName("Kanban Board")
        .description("What you're working on, and what's next.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled() // the views pad themselves
    }
}

/// Reads the widget environment and hands it to the shared views.
private struct BoardWidgetEntryView: View {
    let entry: BoardEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        BoardWidgetContent(entry: entry, family: family)
            .environment(\.kanbanFullColor, renderingMode == .fullColor)
    }
}

/// "→": moves the card one column forward via the App Intent.
struct MoveForwardButton: View {
    let card: TaskCard
    var startLabel = false

    var body: some View {
        if let target = card.column.widgetForward {
            Button(intent: MoveForwardIntent(cardID: card.id)) {
                MoveForwardGlyph(card: card, startLabel: startLabel)
            }
            .buttonStyle(.plain)
            .widgetAccentable()
            .accessibilityLabel("Move \(card.title) to \(target.title)")
        }
    }
}

/// Tapping a card opens the app with it selected.
struct CardLink<Content: View>: View {
    let card: TaskCard
    @ViewBuilder let content: () -> Content

    var body: some View {
        Link(destination: DeepLink.card(card.id), label: content)
    }
}
