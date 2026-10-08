// FormID index tests over synthetic in-code plugins (ESMFixture).

import FormatsTesting
import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct ESMFormIDIndexTests {
    /// WRLD -> exterior block -> CELL 0x2B with a temporary REFR 0x3C, plus a
    /// top-level DOOR 0x50 and a duplicate 0x50 STAT later in the file.
    private static func plugin() throws -> ESMFile {
        let refr = ESMFixture.record(
            "REFR",
            formID: 0x3C,
            data: ESMFixture.field("EDID", ESMFixture.zstring("Ref"))
        )
        let temporary = ESMFixture.childGroup(parent: 0x2B, groupType: 9, contents: refr)
        let cell = ESMFixture.record("CELL", formID: 0x2B, data: Data())
        let cellChildren = ESMFixture.childGroup(parent: 0x2B, groupType: 6, contents: temporary)
        let block = ESMFixture.exteriorBlock(
            x: 0,
            y: 0,
            groupType: 4,
            contents: cell + cellChildren
        )
        let worldChildren = ESMFixture.childGroup(parent: 0x1A, groupType: 1, contents: block)
        let wrld = ESMFixture.record("WRLD", formID: 0x1A, data: Data())
        let door = ESMFixture.record("DOOR", formID: 0x50, data: Data())
        let duplicate = ESMFixture.record("STAT", formID: 0x50, data: Data())
        return try ESMFile(data: ESMFixture.tes4()
            + ESMFixture.topGroup("DOOR", contents: door)
            + ESMFixture.topGroup("STAT", contents: duplicate)
            + ESMFixture.topGroup("WRLD", contents: wrld + worldChildren))
    }

    @Test func findsTheSameRecordsAsAWalk() throws {
        let file = try Self.plugin()
        let index = ESMFormIDIndex(file: file)
        for formID: UInt32 in [0x1A, 0x2B, 0x3C, 0x50] {
            let walked = try #require(ESMWalk.record(withFormID: formID, in: file))
            let indexed = try #require(index.record(withFormID: formID))
            #expect(indexed.type == walked.type)
            #expect(indexed.dataRange == walked.dataRange)
        }
        #expect(try index.record(withFormID: 0x3C)?.fields().first?.type == "EDID")
    }

    @Test func keepsTheFirstRecordOfADuplicatedFormID() throws {
        let index = try ESMFormIDIndex(file: Self.plugin())
        #expect(index.record(withFormID: 0x50)?.type == "DOOR")
        #expect(index.count == 4)
    }

    @Test func missingAndNullFormIDsReturnNil() throws {
        let index = try ESMFormIDIndex(file: Self.plugin())
        #expect(index.record(withFormID: 0) == nil)
        #expect(index.record(withFormID: 0x99) == nil)
    }

    @Test func recordsTheCellThatHoldsAReference() throws {
        let index = try ESMFormIDIndex(file: Self.plugin())
        #expect(index.cellFormID(containing: 0x3C) == 0x2B)
        #expect(index.cellFormID(containing: 0x2B) == nil)
        #expect(index.cellFormID(containing: 0x50) == nil)
    }
}
