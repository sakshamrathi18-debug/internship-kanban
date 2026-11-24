import Foundation
import KanbanCore
import WidgetKit

struct BoardProvider: TimelineProvider {
    /// Must be synchronous: fixed sample data, no file access.
    func placeholder(in context: Context) -> BoardEntry {
        BoardEntry(date: Date(), content: .board(WidgetData.sample))
    }

    func getSnapshot(in context: Context, completion: @escaping (BoardEntry) -> Void) {
        let content = WidgetData.load()
        if context.isPreview, case .noData = content {
            completion(BoardEntry(date: Date(), content: .board(WidgetData.sample))) // the gallery shows something useful
        } else {
            completion(BoardEntry(date: Date(), content: content))
        }
    }

    /// Now, plus a fresh entry just after local midnight. The app also asks for
    /// a reload after each (debounced) save.
    func getTimeline(in context: Context, completion: @escaping (Timeline<BoardEntry>) -> Void) {
        let now = Date()
        let content = WidgetData.load()
        var entries = [BoardEntry(date: now, content: content)]
        if let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 5),
                                                    matchingPolicy: .nextTime) {
            entries.append(BoardEntry(date: midnight, content: content))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}
