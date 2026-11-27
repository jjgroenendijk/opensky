// Which flag bits and enum cases engine code tests, as `tools/lint-index/record-field-reads.py`
// lists them from the index store, and the gap rows they give a field census
// (docs/tools/gaps.md, "Record flag bits" and "Record enum values").

import Foundation
import OpenSkyFormatsCore

nonisolated public struct RecordValueReads: Sendable, Equatable {
    public enum ParseError: Error, Equatable {
        /// A line that is not one of the three row shapes.
        case malformedLine(Int)
    }

    /// One named bit of an `OptionSet` type.
    public struct Bit: Sendable, Equatable {
        public let name: String
        public let isRead: Bool

        public init(name: String, isRead: Bool) {
            self.name = name
            self.isRead = isRead
        }
    }

    /// Each `OptionSet` type of the record module, with its named single bits.
    public let flagTypes: [String: [UInt64: Bit]]
    /// Each enum case keyed `Type.case`, and whether engine code names it.
    public let cases: [String: Bool]

    public init(flagTypes: [String: [UInt64: Bit]], cases: [String: Bool]) {
        self.flagTypes = flagTypes
        self.cases = cases
    }

    /// Rows `flags<TAB>Type`, `read|unread<TAB>bit<TAB>Type<TAB>0x8<TAB>name`, and
    /// `read|unread<TAB>case<TAB>Type.case`.
    public init(text: String) throws(ParseError) {
        var flagTypes: [String: [UInt64: Bit]] = [:]
        var cases: [String: Bool] = [:]
        for (number, line) in text.split(separator: "\n").enumerated() {
            let parts = line.split(separator: "\t").map(String.init)
            let isRead = parts.first == "read"
            switch (parts.first, parts.count > 1 ? parts[1] : nil, parts.count) {
            case ("flags", _, 2):
                flagTypes[parts[1]] = flagTypes[parts[1]] ?? [:]
            case ("read", "bit", 5), ("unread", "bit", 5):
                guard let bit = UInt64(parts[3].dropFirst(2), radix: 16) else {
                    throw .malformedLine(number + 1)
                }
                flagTypes[parts[2], default: [:]][bit] = Bit(name: parts[4], isRead: isRead)
            case ("read", "case", 3), ("unread", "case", 3):
                cases[parts[2]] = isRead
            default:
                throw .malformedLine(number + 1)
            }
        }
        self.flagTypes = flagTypes
        self.cases = cases
    }
}

nonisolated public struct RecordValueGaps: Sendable, Equatable {
    /// The done and left rows of one area.
    public struct Area: Sendable, Equatable {
        /// Distinct values the data uses and engine code tests.
        public var done = 0
        /// Values the data uses that no engine code tests, most records first.
        public var left: [RecordFieldGaps.Row] = []
        /// Types the data uses that the list does not name: the index is older than the code.
        public var unknown: Set<String> = []
    }

    public let flags: Area
    public let enums: Area

    public init(census: RecordFieldCensus, reads: RecordValueReads) {
        var flags = Area()
        var enums = Area()
        for (value, field) in census.values {
            let types = Self.recordTypes(field)
            switch value.kind {
            case let .bit(bit):
                guard let named = reads.flagTypes[value.type] else {
                    flags.unknown.insert(value.type)
                    continue
                }
                let found = named[bit]
                let unused = RecordDataUnused.reason(forBit: bit, of: value.type) != nil
                if found?.isRead == true || unused {
                    flags.done += 1
                } else {
                    let hex = "0x" + String(bit, radix: 16, uppercase: true)
                    let name = "\(value.field) \(hex) \(found?.name ?? "unnamed") (\(types))"
                    flags.left.append(RecordFieldGaps.Row(name: name, records: field.records))
                }
            case let .enumCase(name):
                if RecordDataUnused.reason(forCase: name, of: value.type) != nil {
                    enums.done += 1
                    continue
                }
                switch reads.cases["\(value.type).\(name)"] {
                case true?:
                    enums.done += 1
                case nil where !name.hasPrefix("unknown"):
                    enums.unknown.insert(value.type)
                default:
                    let row = "\(value.field) .\(name) (\(types))"
                    enums.left.append(RecordFieldGaps.Row(name: row, records: field.records))
                }
            }
        }
        flags.left.sort(by: Self.ranked)
        enums.left.sort(by: Self.ranked)
        self.flags = flags
        self.enums = enums
    }

    private static func ranked(_ lhs: RecordFieldGaps.Row, _ rhs: RecordFieldGaps.Row) -> Bool {
        lhs.records == rhs.records ? lhs.name < rhs.name : lhs.records > rhs.records
    }

    private static func recordTypes(_ field: RecordFieldCensus.Field) -> String {
        let types = field.recordTypes.sorted {
            $0.value == $1.value ? $0.key.description < $1.key.description : $0.value > $1.value
        }
        let named = types.prefix(3).map(\.key.description).joined(separator: ", ")
        return named + (types.count > 3 ? ", +\(types.count - 3)" : "")
    }
}
