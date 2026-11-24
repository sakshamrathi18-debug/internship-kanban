import AppKit
import KanbanCore
import Observation
import SwiftUI
import WidgetKit

/// Owns the store and the window's UI state, and ties them to the app's
/// lifecycle: flush on quit/backgrounding, re-read on activation, refresh at
/// midnight, reload the widget after saves.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let store: BoardStore
    let ui = BoardUI()
    let drag = DragController()

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var minuteTimer: Timer?
    @ObservationIgnored private var widgetSignature: Int

    private init() {
        let store = BoardStore(persistence: FileBoardPersistence())
        self.store = store
        widgetSignature = store.board.widgetSignature
        drag.store = store
        drag.ui = ui
        store.onDidSave = { [weak self] board in self?.reloadWidgetIfNeeded(board) }
        store.startObservingDisk()
        observeLifecycle()
        // After an update, redraw any widget already on the desktop.
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Deep links

    func open(_ url: URL) {
        NSApp.activate()
        if let id = DeepLink.cardID(from: url) {
            ui.reveal(id, in: store)
        }
    }

    // MARK: - Undo routing

    /// ⌘Z: a text field with its own undo history gets it first; otherwise
    /// it undoes the last board change.
    func performUndo() {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.allowsUndo,
           let undoManager = textView.undoManager, undoManager.canUndo {
            undoManager.undo()
            return
        }
        withAnimation(Motion.spring(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) { store.undo() }
    }

    func performRedo() {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.allowsUndo,
           let undoManager = textView.undoManager, undoManager.canRedo {
            undoManager.redo()
            return
        }
        withAnimation(Motion.spring(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) { store.redo() }
    }

    // MARK: - Widget

    /// Widget reloads are budgeted, so only ask when something the widget
    /// shows (titles, columns, order, priority, dates) actually changed.
    private func reloadWidgetIfNeeded(_ board: Board) {
        let signature = board.widgetSignature
        guard signature != widgetSignature else { return }
        widgetSignature = signature
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.board)
    }

    // MARK: - Lifecycle

    private func observeLifecycle() {
        func on(_ name: Notification.Name, in center: NotificationCenter = .default, _ action: @escaping @MainActor (AppModel) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    action(self)
                }
            })
        }

        // Pick up anything the widget did while we were in the background.
        on(NSApplication.didBecomeActiveNotification) { model in
            model.store.refreshDay()
            model.store.scheduleReload()
        }
        // "Backgrounding": write everything now.
        on(NSApplication.didResignActiveNotification) { model in
            model.drag.cancel()
            model.store.flush()
        }
        on(NSApplication.willTerminateNotification) { $0.store.flush() }
        on(NSWindow.willCloseNotification) { $0.store.flush() }
        // Midnight, time-zone changes and wake: "Today"/"Overdue" labels and the archive rule.
        on(.NSCalendarDayChanged) { $0.store.refreshDay() }
        on(.NSSystemTimeZoneDidChange) { $0.store.refreshDay() }
        on(NSWorkspace.didWakeNotification, in: NSWorkspace.shared.notificationCenter) { model in
            model.store.refreshDay()
            model.store.scheduleReload()
        }

        // Belt and braces for the day change (sleep, clock changes).
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.refreshDay() }
        }
        RunLoop.main.add(timer, forMode: .common)
        minuteTimer = timer
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        MainActor.assumeIsolated {
            WidgetSnapshots.renderIfRequested()
            DebugDemo.applyAppearance()
        }
        #endif
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { AppModel.shared.store.flush() }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.store.flush() }
    }
}
