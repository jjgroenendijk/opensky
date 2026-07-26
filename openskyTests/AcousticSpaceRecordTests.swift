// ASPC acoustic-space decoder coverage over synthetic ESM field bytes only.
// Layout: xEdit dev-4.1.6 wbDefinitionsTES5.pas lines 5401-5407; see
// docs/formats/acoustic-space.md. The RDAT field here is a 4-byte REGN FormID,
// not the 8-byte area header the REGN record uses (Region.swift).

import Foundation
@testable import opensky
import Testing

struct AcousticSpaceRecordTests {
    @Test func decodesCompleteAcousticSpace() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("CaveAcoustic"))
            + ESMFixture.field("SNAM", formID(0x100))
            + ESMFixture.field("RDAT", formID(0x200))
            + ESMFixture.field("BNAM", formID(0x300))
        let aspc = try AcousticSpace(record: record(ESMFixture.record(
            "ASPC", formID: 0x10, data: fields
        )))

        #expect(aspc.formID == FormID(0x10))
        #expect(aspc.editorID == "CaveAcoustic")
        #expect(aspc.ambientSound == FormID(0x100))
        #expect(aspc.borrowedRegion == FormID(0x200))
        #expect(aspc.reverbModel == FormID(0x300))
    }

    @Test func decodesBareAcousticSpace() throws {
        let aspc = try AcousticSpace(record: record(ESMFixture.record(
            "ASPC", data: ESMFixture.field("EDID", ESMFixture.zstring("Bare"))
        )))
        #expect(aspc.ambientSound == nil)
        #expect(aspc.borrowedRegion == nil)
        #expect(aspc.reverbModel == nil)
    }

    @Test func skipsMalformedFormIDFields() throws {
        // Wrong-size fields are skipped rather than throwing.
        let fields = ESMFixture.field("SNAM", Data(count: 3))
            + ESMFixture.field("RDAT", Data(count: 5))
            + ESMFixture.field("BNAM", Data(count: 2))
        let aspc = try AcousticSpace(record: record(ESMFixture.record(
            "ASPC", formID: 0x11, data: fields
        )))
        #expect(aspc.ambientSound == nil)
        #expect(aspc.borrowedRegion == nil)
        #expect(aspc.reverbModel == nil)
    }

    @Test func ignoresNullFormIDs() throws {
        let fields = ESMFixture.field("SNAM", formID(0))
            + ESMFixture.field("RDAT", formID(0))
        let aspc = try AcousticSpace(record: record(ESMFixture.record(
            "ASPC", formID: 0x12, data: fields
        )))
        #expect(aspc.ambientSound == nil)
        #expect(aspc.borrowedRegion == nil)
    }

    @Test func wrongRecordTypeThrows() throws {
        #expect(throws: ESMError.self) {
            _ = try AcousticSpace(record: record(ESMFixture.record(
                "STAT", data: Data()
            )))
        }
    }

    private func formID(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }

    private func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }
}
