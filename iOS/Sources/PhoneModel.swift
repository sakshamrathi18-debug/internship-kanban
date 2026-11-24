import KanbanCore
import Observation
import SwiftUI
import UIKit
import WidgetKit

/// Owns the store and the screen's UI state, and ties them to the app's
/// lifecycle: flush when backgrounded, re-read when active (the widget may
/// have moved a card), refresh at midnight, reload the widget after saves.
@MainActor
@Observable
final class PhoneModel {
    static let shared = PhoneModel()

    let store: BoardStore
    let ui = PhoneUI()

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var widgetSignature: Int

    private init() {
        let store = BoardStore(persistence: FileBoardPersistence())
        self.store = store
        widgetSignature = store.board.widgetSignature
        store.onDidSave = { [weak self] board in self?.reloadWidgetIfNeeded(board) }
        store.startObservingDisk()
        observeDayChanges()
        WidgetCenter.shared.reloadAllTimelines()
        #if DEBUG
        PhoneDemo.apply(ui: ui, store: store)
        #endif
    }

    // MARK: - Deep links

    func open(_ url: URL) {
        if let id = DeepLink.cardID(from: url) {
            ui.reveal(id, in: store)
        }
    }

    // MARK: - Lifecycle

    func didBecomeActive() {
        store.refreshDay()
        store.scheduleReload()
    }

    func didEnterBackground() {
        // Ask for a moment of background time so the last edit reaches disk.
        let task = UIApplication.shared.beginBackgroundTask(withName: "Save board")
        store.flush()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.board)
        UIApplication.shared.endBackgroundTask(task)
    }

    private func observeDayChanges() {
        for name in [Notification.Name.NSCalendarDayChanged, UIApplication.significantTimeChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.store.refreshDay() }
            })
        }
    }

    // MARK: - Widget

    /// Widget reloads are budgeted, so only ask when something it shows changed.
    private func reloadWidgetIfNeeded(_ board: Board) {
        let signature = board.widgetSignature
        guard signature != widgetSignature else { return }
        widgetSignature = signature
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.board)
    }
}
