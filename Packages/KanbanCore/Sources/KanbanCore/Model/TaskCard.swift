import Foundation

public struct TaskCard: Identifiable, Codable, Equatable, Hashable, Sendable {
    public static let maxTitleLength = 200
    public static let maxNextStepLength = 200

    public let id: UUID
    public var title: String
    public var nextStep: String
    public var waitingOn: String
    public var category: String
    public var priority: Priority
    public var column: Column
    public var sortIndex: Double
    public var startDate: CalendarDay?
    public var dueDate: CalendarDay?
    public var createdAt: Date
    public var updatedAt: Date
    /// Set when the card moves into Done, cleared when it moves out.
    public var completedAt: Date?
    public var isArchived: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        nextStep: String = "",
        waitingOn: String = "",
        category: String = "",
        priority: Priority = .none,
        column: Column,
        sortIndex: Double,
        startDate: CalendarDay? = nil,
        dueDate: CalendarDay? = nil,
        createdAt: Date,
        updatedAt: Date? = nil,
        completedAt: Date? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = TaskCard.cleanTitle(title)
        self.nextStep = String(nextStep.prefix(TaskCard.maxNextStepLength))
        self.waitingOn = waitingOn
        self.category = category
        self.priority = priority
        self.column = column
        self.sortIndex = sortIndex
        self.startDate = startDate
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.completedAt = completedAt ?? (column == .done ? createdAt : nil)
        self.isArchived = isArchived
    }

    /// Trims and caps a title. Returns "" for whitespace-only input.
    public static func cleanTitle(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTitleLength))
    }

    public var isDone: Bool { column == .done }

    /// True when the due date is earlier than the start date (allowed, but flagged).
    public var dueBeforeStart: Bool {
        if let start = startDate, let due = dueDate { return due < start }
        return false
    }

    /// Everything except bookkeeping, for "did anything really change?" checks.
    public func hasSameContent(as other: TaskCard) -> Bool {
        title == other.title && nextStep == other.nextStep && waitingOn == other.waitingOn
            && category == other.category && priority == other.priority && column == other.column
            && sortIndex == other.sortIndex && startDate == other.startDate && dueDate == other.dueDate
            && completedAt == other.completedAt && isArchived == other.isArchived
    }

    // Tolerant decoding: hand-edited or older files with missing optional
    // fields still load. Only id, title and column are required.
    private enum CodingKeys: String, CodingKey {
        case id, title, nextStep, waitingOn, category, priority, column, sortIndex
        case startDate, dueDate, createdAt, updatedAt, completedAt, isArchived
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        nextStep = try c.decodeIfPresent(String.self, forKey: .nextStep) ?? ""
        waitingOn = try c.decodeIfPresent(String.self, forKey: .waitingOn) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        priority = (try? c.decodeIfPresent(Priority.self, forKey: .priority)) ?? Priority.none
        column = try c.decode(Column.self, forKey: .column)
        sortIndex = try c.decodeIfPresent(Double.self, forKey: .sortIndex) ?? 0
        startDate = try? c.decodeIfPresent(CalendarDay.self, forKey: .startDate)
        dueDate = try? c.decodeIfPresent(CalendarDay.self, forKey: .dueDate)
        let created = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        createdAt = created
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? created
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(nextStep, forKey: .nextStep)
        try c.encode(waitingOn, forKey: .waitingOn)
        try c.encode(category, forKey: .category)
        try c.encode(priority, forKey: .priority)
        try c.encode(column, forKey: .column)
        try c.encode(sortIndex, forKey: .sortIndex)
        try c.encodeIfPresent(startDate, forKey: .startDate)
        try c.encodeIfPresent(dueDate, forKey: .dueDate)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encode(isArchived, forKey: .isArchived)
    }
}
