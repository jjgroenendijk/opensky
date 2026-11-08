// FLOR, TACT, FURN, TREE, and ACTI world-object fields on synthetic ModelBase
// records. Layout: docs/formats/world-records.md.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct WorldObjectRecordTests {
    private static func base(_ type: String, _ fields: Data) throws -> ModelBase {
        try ModelBase(
            record: ESMFixture.parseRecord(ESMFixture.record(type, formID: 0x42, data: fields)),
            localized: false
        )
    }

    private static func link(_ type: String, _ value: UInt32) -> Data {
        InventoryFixture.formIDField(type, value)
    }

    @Test func decodesFloraProduce() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("MountainFlower01Blue"))
            + ESMFixture.field("FULL", ESMFixture.zstring("Blue Mountain Flower"))
            + InventoryFixture.keywordFields([0x10])
            + ESMFixture.field("RNAM", ESMFixture.zstring("Pick"))
            + ESMFixture.field("FNAM", Data([0, 0]))
            + Self.link("PFIG", 0x0007_7194)
            + Self.link("SNAM", 0x0005_33AE)
            + ESMFixture.field("PFPC", Data([100, 90, 80, 0]))
        let flora = try Self.base("FLOR", fields)
        #expect(flora.recordType == "FLOR")
        #expect(flora.activateTextOverride == .inline("Pick"))
        #expect(flora.keywords.keywords == [FormID(0x10)])
        #expect(flora.produce == HarvestProduce(
            ingredient: FormID(0x0007_7194),
            harvestSound: FormID(0x0005_33AE),
            seasonalChance: [100, 90, 80, 0]
        ))
        #expect(flora.sounds == nil)
        #expect(flora.details.flags == 0)
        #expect(flora.skipped.isEmpty)
    }

    @Test func decodesTreeProduce() throws {
        let fields = Self.link("PFIG", 0) + ESMFixture.field("PFPC", Data([1, 2, 3, 4]))
        let tree = try Self.base("TREE", fields)
        #expect(tree.produce?.ingredient == nil)
        #expect(tree.produce?.seasonalChance == [1, 2, 3, 4])
        #expect(try Self.base("TREE", Data()).produce == nil)
    }

    @Test func decodesTalkingActivator() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("TalkingSkull"))
            + Self.link("SNAM", 0x30)
            + Self.link("VNAM", 0x0001_3AD5)
        let tact = try Self.base("TACT", fields)
        #expect(tact.voiceType == FormID(0x0001_3AD5))
        #expect(tact.sounds?.loop == FormID(0x30))
        #expect(tact.sounds?.activation == nil)
    }

    @Test func decodesFurnitureWorkbench() throws {
        let fields = InventoryFixture.keywordFields([0x0008_8105])
            + Self.link("KNAM", 0x50)
            + ESMFixture.field("WBDT", Data([2, 10]))
        let forge = try Self.base("FURN", fields)
        #expect(forge.keywords.contains(FormID(0x0008_8105)))
        #expect(forge.interactionKeyword == FormID(0x50))
        #expect(forge.workbench == Workbench(benchType: .smithingWeapon, skillIndex: 10))
        #expect(forge.workbench?.skillName == "Smithing")
        #expect(forge.skipped.isEmpty)
    }

    @Test func workbenchWithoutSkillHasNoSkillName() throws {
        let bench = try Self.base("FURN", ESMFixture.field("WBDT", Data([1, 0xFF])))
        #expect(bench.workbench?.skillIndex == -1)
        #expect(bench.workbench?.skillName == nil)
    }

    @Test func decodesActivatorKeywords() throws {
        let fields = InventoryFixture.keywordFields([0x60, 0x61]) + Self.link("KNAM", 0x62)
        let activator = try Self.base("ACTI", fields)
        #expect(activator.keywords.keywords == [FormID(0x60), FormID(0x61)])
        #expect(activator.interactionKeyword == FormID(0x62))
    }

    /// A field read only for another type stays unread, so WBDT on an ACTI is tallied.
    @Test func workbenchDataIsReadOnlyOnFurniture() throws {
        let activator = try Self.base("ACTI", ESMFixture.field("WBDT", Data([2, 10])))
        #expect(activator.workbench == nil)
        #expect(activator.skipped.counts == [.unknownField("WBDT"): 1])
    }

    /// A short field costs only itself; the rest of the record still decodes.
    @Test func survivesTruncatedFields() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("ShortFlora"))
            + ESMFixture.field("PFIG", Data([1, 2]))
            + ESMFixture.field("PFPC", Data([1]))
        let flora = try Self.base("FLOR", fields)
        #expect(flora.editorID == "ShortFlora")
        #expect(flora.produce == nil)
        #expect(flora.skipped.counts == [.malformedField("PFIG"): 1, .malformedField("PFPC"): 1])

        let bench = try Self.base("FURN", ESMFixture.field("WBDT", Data([3])))
        #expect(bench.workbench == nil)
        #expect(bench.skipped.counts == [.malformedField("WBDT"): 1])
    }

    @Test func workbenchTypeKeepsUnknownValues() {
        for raw: UInt8 in 0 ... 9 {
            #expect(WorkbenchType(rawValue: raw).rawValue == raw)
        }
        #expect(WorkbenchType(rawValue: 5) == .alchemy)
        #expect(WorkbenchType(rawValue: 7) == .smithingArmor)
        #expect(WorkbenchType(rawValue: 9) == .unknown(9))
    }
}
