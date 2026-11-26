// RecordFieldCensus, RecordFieldReads, and RecordFieldGaps: which fields synthetic values
// fill, and the gap rows a read list gives them.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyTagsTesting
import Testing

/// Internal, not private: reflection names a private type by an unknown context.
enum FieldCensusFixture {
    struct Sound: Equatable {
        let formID: UInt32
        let volume: Float
    }

    enum Shape {
        case box(Sound)
        case none
    }

    struct Door {
        let name: String
        let open: Sound?
        let close: Sound?
        let sounds: [Sound]
        let locked: Bool
        let shape: Shape
        let skipped: Int
    }
}

private typealias Door = FieldCensusFixture.Door
private typealias Sound = FieldCensusFixture.Sound

@Suite(.tags(.parser))
struct RecordFieldCensusTests {
    private static let module = "OpenSkyFormatsESMTests"

    private static func key(_ field: String) -> String {
        "FieldCensusFixture.\(field)"
    }

    @Test func countsTheFieldsAValueFills() {
        var census = RecordFieldCensus(module: Self.module)
        let filled = Door(
            name: "Gate", open: Sound(formID: 7, volume: 0), close: nil,
            sounds: [Sound(formID: 0, volume: 0.5), Sound(formID: 2, volume: 0)],
            locked: false, shape: .box(Sound(formID: 3, volume: 0)), skipped: 4
        )
        let empty = Door(
            name: "", open: nil, close: nil, sounds: [], locked: true, shape: .none, skipped: 0
        )
        census.record(filled, type: "DOOR")
        census.record(empty, type: "ACTI")

        let expected = [
            "Door.name": 1, "Door.open": 1, "Door.sounds": 1, "Door.locked": 1, "Door.shape": 2,
            "Sound.formID": 1, "Sound.volume": 1
        ]
        #expect(census.fields.mapValues(\.records) == Dictionary(
            uniqueKeysWithValues: expected.map { (Self.key($0.key), $0.value) }
        ))
        #expect(census.fields[Self.key("Door.shape")]?.recordTypes == ["DOOR": 1, "ACTI": 1])
    }

    @Test func typesOfOtherModulesAreValuesNotFields() {
        var census = RecordFieldCensus()
        census.record(Door(
            name: "Gate", open: nil, close: nil, sounds: [], locked: false, shape: .none,
            skipped: 0
        ), type: "DOOR")
        #expect(census.fields.isEmpty)
    }

    @Test func readsListParsesAndRejectsAMalformedLine() throws {
        let reads = try RecordFieldReads(text: "read\tDoor.name\nunread\tDoor.open\n")
        #expect(reads.fields == ["Door.name": true, "Door.open": false])
        #expect(throws: RecordFieldReads.ParseError.malformedLine(2)) {
            try RecordFieldReads(text: "read\tDoor.name\nmaybe Door.open\n")
        }
    }

    @Test func gapsRankTheUnreadFieldsAndNameTheUnknownOnes() {
        var census = RecordFieldCensus(module: Self.module)
        let door = Door(
            name: "Gate", open: Sound(formID: 7, volume: 1), close: nil, sounds: [],
            locked: true, shape: .none, skipped: 0
        )
        census.record(door, type: "DOOR")
        census.record(door, type: "DOOR")
        census.record(door, type: "CONT")
        let read = [
            "Door.name": true, "Door.shape": true, "Door.locked": false, "Sound.formID": false,
            "Sound.volume": false
        ]
        let reads = RecordFieldReads(fields: Dictionary(
            uniqueKeysWithValues: read.map { (Self.key($0.key), $0.value) }
        ))

        let gaps = RecordFieldGaps(census: census, reads: reads)

        #expect(gaps.done == 2)
        #expect(gaps.left.map(\.name) == [
            "FieldCensusFixture.Door.locked (DOOR, CONT)",
            "FieldCensusFixture.Sound.formID (DOOR, CONT)",
            "FieldCensusFixture.Sound.volume (DOOR, CONT)"
        ])
        #expect(gaps.left.map(\.records) == [3, 3, 3])
        #expect(gaps.unknown == ["FieldCensusFixture.Door.open"])
    }
}
