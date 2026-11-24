import Foundation

/// Named `BoardSettings` rather than `Settings` so it doesn't collide with
/// SwiftUI's `Settings` scene in the app target.
public struct BoardSettings: Codable, Equatable, Sendable {
    public static let wipLimitRange = 1...10
    public static let archiveDaysRange = 1...90

    /// `nil` turns the WIP nudge off.
    public var wipLimit: Int?
    public var archiveAfterDays: Int
    public var showSummaryStrip: Bool

    public init(wipLimit: Int? = 3, archiveAfterDays: Int = 14, showSummaryStrip: Bool = true) {
        self.wipLimit = wipLimit
        self.archiveAfterDays = archiveAfterDays
        self.showSummaryStrip = showSummaryStrip
    }

    private enum CodingKeys: String, CodingKey { case wipLimit, archiveAfterDays, showSummaryStrip }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A missing key means "default"; an explicit null means "off".
        if c.contains(.wipLimit) {
            wipLimit = try c.decodeIfPresent(Int.self, forKey: .wipLimit)
        } else {
            wipLimit = 3
        }
        archiveAfterDays = try c.decodeIfPresent(Int.self, forKey: .archiveAfterDays) ?? 14
        showSummaryStrip = try c.decodeIfPresent(Bool.self, forKey: .showSummaryStrip) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(wipLimit, forKey: .wipLimit) // encodes null when off
        try c.encode(archiveAfterDays, forKey: .archiveAfterDays)
        try c.encode(showSummaryStrip, forKey: .showSummaryStrip)
    }
}

public struct BoardFile: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var cards: [TaskCard]
    public var settings: BoardSettings

    public init(schemaVersion: Int = BoardFile.currentSchemaVersion, cards: [TaskCard], settings: BoardSettings = BoardSettings()) {
        self.schemaVersion = schemaVersion
        self.cards = cards
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, cards, settings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        cards = try c.decode([TaskCard].self, forKey: .cards)
        settings = try c.decodeIfPresent(BoardSettings.self, forKey: .settings) ?? BoardSettings()
    }
}
