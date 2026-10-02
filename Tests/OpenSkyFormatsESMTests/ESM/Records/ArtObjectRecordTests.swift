// ARTO over synthetic records. Layout: docs/formats/art-objects.md.

import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct ArtObjectRecordTests {
    private static func record(_ fields: Data, type: String = "ARTO") throws -> ESMRecord {
        try ESMFixture.parseRecord(ESMFixture.record(type, formID: 0x42, data: fields))
    }

    private static func artType(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return ESMFixture.field("DNAM", data)
    }

    @Test func decodesArtObject() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("FireCloakArt"))
            + ESMFixture.field("OBND", InventoryFixture.boundsData())
            + ESMFixture.field("MODL", ESMFixture.zstring("magic\\firecloak.nif"))
            + ESMFixture.field("MODT", Data(count: 12))
            + Self.artType(1)
        let art = try ArtObject(record: Self.record(fields))
        #expect(art.formID == FormID(0x42))
        #expect(art.editorID == "FireCloakArt")
        #expect(art.bounds?.isEmpty == false)
        #expect(art.modelPath == "magic\\firecloak.nif")
        #expect(art.artType == .magicHitEffect)
        #expect(art.skipped.counts == [.unknownField("MODT"): 1])
    }

    @Test func rejectsOtherRecordTypes() throws {
        #expect(throws: ESMError.self) {
            try ArtObject(record: Self.record(Data(), type: "STAT"))
        }
    }

    /// A short DNAM costs only itself.
    @Test func survivesTruncatedArtType() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("ShortArt"))
            + ESMFixture.field("DNAM", Data([1, 0]))
        let art = try ArtObject(record: Self.record(fields))
        #expect(art.editorID == "ShortArt")
        #expect(art.artType == nil)
        #expect(art.skipped.counts == [.malformedField("DNAM"): 1])
    }

    @Test func artTypeKeepsUnknownValues() {
        for raw: UInt32 in [0, 1, 2, 7] {
            #expect(ArtType(rawValue: raw).rawValue == raw)
        }
        #expect(ArtType(rawValue: 0) == .magicCasting)
        #expect(ArtType(rawValue: 2) == .enchantmentEffect)
        #expect(ArtType(rawValue: 7) == .unknown(7))
    }
}
