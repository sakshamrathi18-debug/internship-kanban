import KanbanCore
import SwiftUI

// The apps compile the widget's views for previews and snapshots, but have no
// App Intents or widget links; these stand-ins look the same.

/// The app's stand-in for the widget's "→" button: same look, no intent.
/// Used by the debug renderers.
struct MoveForwardButton: View {
    let card: TaskCard
    var startLabel = false

    var body: some View {
        if card.column.widgetForward != nil {
            MoveForwardGlyph(card: card, startLabel: startLabel)
        }
    }
}

/// The app's stand-in for the widget's card link (image rendering can't draw `Link`).
struct CardLink<Content: View>: View {
    let card: TaskCard
    @ViewBuilder let content: () -> Content

    var body: some View { content() }
}
