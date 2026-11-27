// Which record fields engine code reads, as `tools/lint-index/record-field-reads.py` lists
// them from the index store, and the gap rows it gives a field census (docs/tools/gaps.md).

import Foundation
import OpenSkyFormatsCore

nonisolated public struct RecordFieldReads: Sendable, Equatable {
    public enum ParseError: Error, Equatable {
        /// A line that is not `read` or `unread`, a tab, and a field.
        case malformedLine(Int)
    }

    /// Each field the list knows, and whether engine code reads it.
    public let fields: [String: Bool]

    public init(fields: [String: Bool]) {
        self.fields = fields
    }

    public init(text: String) throws(ParseError) {
        var fields: [String: Bool] = [:]
        for (number, line) in text.split(separator: "\n").enumerated() {
            let parts = line.split(separator: "\t")
            guard parts.count == 2, parts[0] == "read" || parts[0] == "unread" else {
                throw .malformedLine(number + 1)
            }
            fields[String(parts[1])] = parts[0] == "read"
        }
        self.fields = fields
    }
}

nonisolated public struct RecordFieldGaps: Sendable, Equatable {
    public struct Row: Sendable, Equatable {
        /// The field, then up to three record types that fill it.
        public let name: String
        /// Records that fill the field.
        public let records: Int
    }

    /// Distinct fields the data fills and engine code reads, or the game does not use.
    public let done: Int
    /// The part of `done` the game does not use (`RecordDataUnused`).
    public let unused: Int
    /// Fields the data fills and only the decoder touches, most used first.
    public let left: [Row]
    /// Fields the data fills that the list does not name: the index is older than the code.
    public let unknown: [String]

    public init(census: RecordFieldCensus, reads: RecordFieldReads) {
        var done = 0
        var unused = 0
        var left: [Row] = []
        var unknown: [String] = []
        for (key, field) in census.fields {
            switch reads.fields[key] {
            case true?:
                done += 1
            case false? where RecordDataUnused.reason(forField: key) != nil:
                done += 1
                unused += 1
            case false?:
                left.append(Row(name: Self.label(key, field), records: field.records))
            case nil:
                unknown.append(key)
            }
        }
        self.done = done
        self.unused = unused
        self.left = left.sorted {
            $0.records == $1.records ? $0.name < $1.name : $0.records > $1.records
        }
        self.unknown = unknown.sorted()
    }

    private static func label(_ key: String, _ field: RecordFieldCensus.Field) -> String {
        let types = field.recordTypes.sorted {
            $0.value == $1.value ? $0.key.description < $1.key.description : $0.value > $1.value
        }
        let named = types.prefix(3).map(\.key.description).joined(separator: ", ")
        let more = types.count > 3 ? ", +\(types.count - 3)" : ""
        return "\(key) (\(named)\(more))"
    }
}
