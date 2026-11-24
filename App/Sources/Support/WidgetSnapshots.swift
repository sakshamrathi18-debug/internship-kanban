import AppKit
import KanbanCore
import SwiftUI
import WidgetKit

#if DEBUG
/// Renders the widget's three sizes to PNGs so the layout can be checked
/// without adding widgets to the desktop:
///
///   KANBAN_WIDGET_SNAPSHOTS=/some/folder "Kanban Board.app/Contents/MacOS/Kanban Board"
///
/// Writes <board>-<size>-<appearance>.png for a few sample boards, then quits.
enum WidgetSnapshots {
    @MainActor
    static func renderIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["KANBAN_WIDGET_SNAPSHOTS"] else { return }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let sizes: [(String, WidgetFamily, CGSize)] = [
            ("small", .systemSmall, CGSize(width: 170, height: 170)),
            ("medium", .systemMedium, CGSize(width: 344, height: 170)),
            ("large", .systemLarge, CGSize(width: 344, height: 344)),
        ]
        let looks: [(String, ColorScheme, Bool)] = [("light", .light, true), ("dark", .dark, true), ("dimmed", .dark, false)]

        for (boardName, entry) in sampleEntries() {
            for (sizeName, family, size) in sizes {
                for (lookName, scheme, fullColor) in looks {
                    let view = BoardWidgetContent(entry: entry, family: family)
                        .environment(\.kanbanFullColor, fullColor)
                        .frame(width: size.width, height: size.height)
                        .background(fullColor ? Palette.widgetBackground : Color(white: 0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .saturation(fullColor ? 1 : 0)
                        .environment(\.colorScheme, scheme)
                        .padding(8)
                        .background(scheme == .dark ? Color(white: 0.30) : Color(white: 0.85))
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    guard let image = renderer.cgImage,
                          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { continue }
                    try? png.write(to: folder.appendingPathComponent("\(boardName)-\(sizeName)-\(lookName).png"))
                }
            }
        }
        exit(0)
    }

    private static func sampleEntries() -> [(String, BoardEntry)] {
        let now = Date()
        let today = CalendarDay.today()
        func board(_ build: (inout Board) -> Void) -> BoardEntry {
            var board = Board()
            build(&board)
            return BoardEntry(date: now, content: .board(board))
        }

        let current = board { b in
            b.add(title: "Post infographic on LinkedIn", column: .todo, now: now) { $0.priority = .medium; $0.category = "LinkedIn" }
            b.add(title: "Recruiter calling — past recruiters' HRs", column: .todo, now: now) {
                $0.priority = .high; $0.startDate = today.adding(days: 2)
            }
            b.add(title: "Complete SIP brochure", column: .done, now: now) { $0.priority = .high }
        }

        let busy = board { b in
            for (title, priority, due) in [
                ("Complete SIP brochure", Priority.high, Optional(today)),
                ("Mock interview with two seniors", .medium, Optional(today.adding(days: 1))),
                ("Finalise alumni contact list for outreach", .low, nil),
                ("Draft pitch email for recruiters", .high, Optional(today.adding(days: -2))),
            ] as [(String, Priority, CalendarDay?)] {
                b.add(title: title, column: .inProgress, now: now) { $0.priority = priority; $0.dueDate = due }
            }
            for (i, title) in ["Post infographic on LinkedIn", "Recruiter calling — past recruiters' HRs", "Update CV with SIP project",
                               "Shortlist 20 target companies", "Book placement office slot", "Prepare case-study notes"].enumerated() {
                b.add(title: title, column: .todo, now: now) {
                    $0.priority = [.medium, .high, .low, .none][i % 4]
                    if i == 2 { $0.dueDate = today.adding(days: 4) }
                }
            }
            b.add(title: "Brochure sign-off from committee", column: .onHold, now: now) { $0.waitingOn = "Committee" }
            b.add(title: "Alumni database access", column: .onHold, now: now) { $0.priority = .medium }
            b.add(title: "Shortlist companies", column: .done, now: now)
        }

        let allClear = board { b in
            b.add(title: "Complete SIP brochure", column: .done, now: now)
            b.add(title: "Post infographic on LinkedIn", column: .done, now: now)
        }

        return [
            ("current", current),
            ("busy", busy),
            ("allclear", allClear),
            ("nodata", BoardEntry(date: now, content: .noData)),
        ]
    }
}
#endif
