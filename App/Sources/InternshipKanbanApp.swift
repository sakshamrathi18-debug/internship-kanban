import KanbanCore
import SwiftUI

@main
struct InternshipKanbanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        // A single `Window`, not a `WindowGroup`: two windows can never edit the board at once.
        Window(AppInfo.name, id: "board") {
            BoardWindow()
                .environment(model.store)
                .environment(model.ui)
                .environment(model.drag)
                .onOpenURL { model.open($0) }
        }
        .defaultSize(width: 1200, height: 760)
        .windowToolbarStyle(.unified(showsTitle: false))
        .handlesExternalEvents(matching: [DeepLink.scheme])
        .commands { BoardCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model.store)
        }
    }
}
