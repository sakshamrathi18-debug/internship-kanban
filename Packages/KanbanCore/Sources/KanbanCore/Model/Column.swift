import Foundation

public enum Column: String, Codable, CaseIterable, Identifiable, Sendable {
    case todo, inProgress, onHold, done

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .todo: "To Do"
        case .inProgress: "In Progress"
        case .onHold: "On Hold"
        case .done: "Done"
        }
    }

    /// The column's policy, shown as the header tooltip.
    public var meaning: String {
        switch self {
        case .todo: "Decided I'll do it, haven't started"
        case .inProgress: "Actively working on it"
        case .onHold: "Started but waiting on someone or something"
        case .done: "Finished"
        }
    }

    /// Board order, for ⌘⌥→ / ⌘⌥←.
    public var next: Column? {
        let all = Column.allCases
        let i = all.firstIndex(of: self)!
        return i + 1 < all.count ? all[i + 1] : nil
    }

    public var previous: Column? {
        let all = Column.allCases
        let i = all.firstIndex(of: self)!
        return i > 0 ? all[i - 1] : nil
    }

    /// The widget's "→" button: To Do → In Progress → Done, On Hold → In Progress.
    public var widgetForward: Column? {
        switch self {
        case .todo: .inProgress
        case .inProgress: .done
        case .onHold: .inProgress
        case .done: nil
        }
    }
}

public enum Priority: String, Codable, CaseIterable, Identifiable, Sendable {
    case high, medium, low, none

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        case .none: "None"
        }
    }

    /// Order for the editor's segmented control: None · Low · Medium · High.
    public static let editorOrder: [Priority] = [.none, .low, .medium, .high]

    /// Panel order on the board: High → Medium → Low → No priority.
    public static let boardOrder: [Priority] = [.high, .medium, .low, .none]

    public var rank: Int { Priority.boardOrder.firstIndex(of: self)! }

    /// The panel label: "HIGH", "MEDIUM", "LOW", "NO PRIORITY".
    public var sectionLabel: String { self == .none ? "NO PRIORITY" : title.uppercased() }
}
