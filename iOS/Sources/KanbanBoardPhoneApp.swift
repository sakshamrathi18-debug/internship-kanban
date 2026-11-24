import KanbanCore
import SwiftUI

@main
struct KanbanBoardPhoneApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let model = PhoneModel.shared

    var body: some Scene {
        WindowGroup {
            BoardScreen()
                .environment(model.store)
                .environment(model.ui)
                .environment(\.boardScale, PhoneMetrics.scale)
                .onOpenURL { model.open($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.didBecomeActive()
            case .background: model.didEnterBackground()
            default: break
            }
        }
    }
}

enum PhoneMetrics {
    /// The Mac's 13 pt card titles read small on a phone; scale the shared pieces up.
    static let scale: CGFloat = 1.18
    /// Side margin for the board's panels.
    static let gutter: CGFloat = 16

    /// iOS 26+ shows the column's status under its title in the top bar;
    /// earlier versions show it as a line above the panels instead.
    static var hasNavigationSubtitle: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
}
