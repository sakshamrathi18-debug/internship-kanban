import Foundation

/// JSON settings shared by every reader and writer of `board.json`.
public enum BoardCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoString(date))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            let string = try container.decode(String.self)
            if let date = parseISO(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(string)")
        }
        return decoder
    }

    public static func encode(_ file: BoardFile) throws -> Data {
        try encoder().encode(file)
    }

    public enum Decoded: Sendable {
        case board(BoardFile)
        /// Written by a newer version of the app. The board is included when it
        /// still decodes, so it can be shown read-only.
        case newerSchema(version: Int, BoardFile?)
        case corrupt
    }

    public static func decode(_ data: Data) -> Decoded {
        struct Probe: Decodable { let schemaVersion: Int }
        let decoder = decoder()
        guard let probe = try? decoder.decode(Probe.self, from: data) else { return .corrupt }
        if probe.schemaVersion > BoardFile.currentSchemaVersion {
            return .newerSchema(version: probe.schemaVersion, try? decoder.decode(BoardFile.self, from: data))
        }
        guard let file = try? decoder.decode(BoardFile.self, from: data) else { return .corrupt }
        return .board(file)
    }

    private static let whole = Date.ISO8601FormatStyle()

    /// "2026-10-10T15:51:31.123Z", built from whole milliseconds so it
    /// round-trips exactly (see `KanbanTime`).
    static func isoString(_ date: Date) -> String {
        let ms = KanbanTime.milliseconds(date)
        let seconds = ms >= 0 ? ms / 1000 : (ms - 999) / 1000
        let fraction = ms - seconds * 1000
        let base = Date(timeIntervalSince1970: TimeInterval(seconds)).formatted(whole) // "…:31Z"
        return String(base.dropLast()) + String(format: ".%03lldZ", fraction)
    }

    static func parseISO(_ string: String) -> Date? {
        guard let dot = string.firstIndex(of: ".") else { return try? whole.parse(string) }
        let digits = string[string.index(after: dot)...].prefix(while: \.isNumber)
        let rest = string[string.index(after: dot)...].dropFirst(digits.count)
        guard let base = try? whole.parse(String(string[..<dot]) + rest), !digits.isEmpty else { return nil }
        let ms = Double(String((digits + "000").prefix(3))) ?? 0
        return KanbanTime.fromMilliseconds((base.timeIntervalSince1970 * 1000).rounded() + ms)
    }
}
