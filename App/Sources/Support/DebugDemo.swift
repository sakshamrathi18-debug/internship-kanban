#if DEBUG
import AppKit
import KanbanCore
import SwiftUI

/// Debug-only launch hooks for taking screenshots of specific states:
///
///   KANBAN_APPEARANCE=light|dark
///   KANBAN_WINDOW_SIZE=760x640
///   KANBAN_DEMO="select:Mock,editor:Mock,search:cv,category:Brochure,toast:Think,archive,settings,composer:todo"
///
/// Items are comma-separated and applied in order shortly after launch.
enum DebugDemo {
    static var environment: [String: String] { ProcessInfo.processInfo.environment }

    @MainActor
    static func applyAppearance() {
        switch environment["KANBAN_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    @MainActor
    static func apply(ui: BoardUI, store: BoardStore) {
        if let size = environment["KANBAN_WINDOW_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2,
           let window = NSApp.windows.first(where: { $0.isVisible && $0.title == "Kanban Board" }) {
            var frame = window.frame
            frame.size = CGSize(width: size[0], height: size[1])
            window.setFrame(frame, display: true)
        }
        guard let demo = environment["KANBAN_DEMO"], !demo.isEmpty else { return }
        func card(_ prefix: String) -> TaskCard? {
            Column.allCases.lazy.flatMap { store.cards(in: $0) }.first { $0.title.hasPrefix(prefix) }
        }
        for item in demo.split(separator: ",").map(String.init) {
            let parts = item.split(separator: ":", maxSplits: 1).map(String.init)
            let value = parts.count > 1 ? parts[1] : ""
            switch parts[0] {
            case "select": if let c = card(value) { ui.select(c.id) }
            case "editor": if let c = card(value) { ui.openEditor(c.id) }
            case "search": ui.showSearch(); ui.searchText = value
            case "category": ui.filter(byCategory: value)
            case "toast": if let c = card(value) { ui.delete(c.id, in: store, animation: nil) }
            case "archive": ui.showArchive = true
            case "composer": ui.openComposer(Column(rawValue: value) ?? .todo)
            case "settings":
                // Press the app menu's own "Settings…" item.
                if let item = NSApp.mainMenu?.items.first?.submenu?.items.first(where: { $0.title.hasPrefix("Settings") }),
                   let action = item.action {
                    NSApp.sendAction(action, to: item.target, from: item)
                }
            case "simdrag":
                // simdrag:x0;y0;x1;y1 in window points from the top-left.
                let v = value.split(separator: ";").compactMap { Double($0) }
                if v.count == 4 { simulateDrag(from: CGPoint(x: v[0], y: v[1]), to: CGPoint(x: v[2], y: v[3])) }
            default: break
            }
        }
    }

    /// Feeds real mouse events through the window, like a trackpad drag.
    @MainActor
    static func simulateDrag(from start: CGPoint, to end: CGPoint) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.title == AppInfo.name }),
              let content = window.contentView else { FileHandle.standardError.write(Data("[sim] no window\n".utf8)); return }
        FileHandle.standardError.write(Data("[sim] window \(window.frame) content \(content.bounds) key \(window.isKeyWindow)\n".utf8))
        func event(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: p.x, y: content.bounds.height - p.y),
                               modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            if let down = event(.leftMouseDown, start) { NSApp.sendEvent(down) }
            for i in 1...30 {
                try? await Task.sleep(for: .milliseconds(16))
                let t = Double(i) / 30
                let p = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
                if let drag = event(.leftMouseDragged, p) { NSApp.sendEvent(drag) }
            }
            try? await Task.sleep(for: .milliseconds(300))
            if let up = event(.leftMouseUp, end) { NSApp.sendEvent(up) }
        }
    }
}
#endif
