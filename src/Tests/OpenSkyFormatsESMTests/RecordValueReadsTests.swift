// RecordFieldCensus values, RecordValueReads, and RecordValueGaps: which flag bits and enum
// cases synthetic values hold, and the gap rows a read list gives them.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyTagsTesting
import Testing

/// Internal, not private: reflection names a private type by an unknown context.
enum ValueCensusFixture {
    struct Flags: OptionSet {
        let rawValue: UInt16
        static let worn = Flags(rawValue: 0x8)
        static let heavy = Flags(rawValue: 0x10)
    }

    enum Kind {
        case light
        case plate
        case unknown(raw: UInt8)
    }

    enum Shown: CustomStringConvertible {
        case hidden
        var description: String {
            "hidden"
        }
    }

    struct Armor {
        let flags: Flags
        let kind: Kind?
        let kinds: [Kind]
        let shown: Shown
        let recordFlags: UInt32
    }
}

private typealias Armor = ValueCensusFixture.Armor

@Suite(.tags(.parser))
struct RecordValueReadsTests {
    private static let module = "OpenSkyFormatsESMTests"
    private static let prefix = "ValueCensusFixture."

    private static func census() -> RecordFieldCensus {
        var census = RecordFieldCensus(module: module)
        census.record(Armor(
            flags: [.worn, .heavy, Flags(rawValue: 0x1)], kind: .plate, kinds: [.light, .plate],
            shown: .hidden, recordFlags: 4
        ), type: "ARMO")
        census.record(Armor(
            flags: [.worn], kind: .unknown(raw: 7), kinds: [], shown: .hidden, recordFlags: 0
        ), type: "WEAP")
        return census
    }

    private typealias Flags = ValueCensusFixture.Flags

    @Test func countsEachBitAndCaseOncePerRecord() {
        let census = Self.census()
        let values = Dictionary(uniqueKeysWithValues: census.values.map { value, field in
            ("\(value.field.dropFirst(Self.prefix.count)) \(value.kind)", field.records)
        })
        #expect(values == [
            "Armor.flags bit(8)": 2, "Armor.flags bit(16)": 1, "Armor.flags bit(1)": 1,
            "Armor.kind enumCase(\"plate\")": 1, "Armor.kind enumCase(\"unknown 7\")": 1,
            "Armor.kinds enumCase(\"light\")": 1, "Armor.kinds enumCase(\"plate\")": 1
        ])
        #expect(census.unnamedEnums == [Self.prefix + "Shown": 2])
        #expect(census.plainFlagFields == [Self.prefix + "Armor.recordFlags": 1])
    }

    @Test func readsListParsesAndRejectsAMalformedLine() throws {
        let reads = try RecordValueReads(text: """
        flags\tArmor.Flags
        read\tbit\tArmor.Flags\t0x8\tworn
        unread\tcase\tArmor.Kind.plate

        """)
        #expect(reads.flagTypes == ["Armor.Flags": [8: .init(name: "worn", isRead: true)]])
        #expect(reads.cases == ["Armor.Kind.plate": false])
        #expect(throws: RecordValueReads.ParseError.malformedLine(1)) {
            try RecordValueReads(text: "read\tbit\tArmor.Flags\tzz\tworn\n")
        }
    }

    @Test func gapsRankUntestedBitsAndUnhandledCases() {
        let flags = Self.prefix + "Flags"
        let kind = Self.prefix + "Kind."
        let reads = RecordValueReads(
            flagTypes: [flags: [
                8: .init(name: "worn", isRead: true), 16: .init(name: "heavy", isRead: false)
            ]],
            cases: [kind + "light": true, kind + "plate": false, kind + "unknown": true]
        )

        let gaps = RecordValueGaps(census: Self.census(), reads: reads)

        let field = Self.prefix + "Armor."
        #expect(gaps.flags.done == 1)
        #expect(gaps.flags.left.map(\.name) == [
            field + "flags 0x1 unnamed (ARMO)", field + "flags 0x10 heavy (ARMO)"
        ])
        #expect(gaps.enums.done == 1)
        #expect(gaps.enums.left.map(\.name) == [
            field + "kind .plate (ARMO)", field + "kind .unknown 7 (WEAP)",
            field + "kinds .plate (ARMO)"
        ])
        #expect(gaps.flags.unknown.isEmpty && gaps.enums.unknown.isEmpty)
    }
}
