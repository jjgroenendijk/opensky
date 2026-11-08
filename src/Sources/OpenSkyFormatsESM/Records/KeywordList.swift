// KSIZ + KWDA keyword array. KSIZ is advisory: the real length is
// `KWDA.count / 4`, and a different KSIZ is kept as `declaredCount` only.
// Layout and sources: docs/formats/keywords.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct KeywordList: Equatable, Sendable {
    /// KWDA entries in file order. Empty when the record carries no keywords.
    public private(set) var keywords: [FormID] = []
    /// KSIZ as written, kept for diagnostics only. Nil when KSIZ is absent —
    /// which is legal, since a KWDA can appear without one in modded data.
    public private(set) var declaredCount: UInt32?

    public init() {}

    /// True when KSIZ is present and disagrees with the decoded KWDA length.
    public var countMismatch: Bool {
        guard let declaredCount else { return false }
        return Int(declaredCount) != keywords.count
    }

    /// Decodes `field` when it is KSIZ or KWDA and reports whether it was
    /// consumed, so a record's field switch can fall through to its own cases.
    public mutating func decode(field: ESMField) throws -> Bool {
        switch field.type {
        case "KSIZ":
            guard field.data.count >= 4 else { return true }
            var reader = BinaryReader(field.data)
            declaredCount = try reader.readUInt32()
        case "KWDA":
            var reader = BinaryReader(field.data)
            // Trailing bytes past the last whole FormID are ignored rather
            // than throwing: the keyword list is advisory data, and losing one
            // malformed tail entry costs less than dropping the record.
            for _ in 0 ..< (field.data.count / 4) {
                try keywords.append(FormID(reader.readUInt32()))
            }
        default:
            return false
        }
        return true
    }

    public func contains(_ keyword: FormID) -> Bool {
        keywords.contains(keyword)
    }
}
