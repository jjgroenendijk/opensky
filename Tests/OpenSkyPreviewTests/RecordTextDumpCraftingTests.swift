// Decoded dump lines for ARTO, COBJ, FLOR, TACT, and FURN. In-code fixtures only.

import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyPreview
import Testing

struct RecordTextDumpCraftingTests {
    private static func dump(_ type: String, _ fields: Data) throws -> String {
        let record = try ESMFixture.parseRecord(ESMFixture.record(type, formID: 0x42, data: fields))
        return RecordTextDump.dump(record: record, localized: false)
    }

    @Test func dumpsArtObject() throws {
        let dump = try Self.dump(
            "ARTO",
            ESMFixture.field("EDID", ESMFixture.zstring("FireCloakArt"))
                + ESMFixture.field("MODL", ESMFixture.zstring("magic\\cloak.nif"))
                + InventoryFixture.formIDField("DNAM", 1)
        )
        #expect(dump.contains(
            "decoded ARTO: editorID FireCloakArt, art type magicHitEffect, model magic\\cloak.nif"
        ))
    }

    @Test func dumpsRecipeWithComponentsAndConditions() throws {
        let bytes = RecipeFixture.recordBytes(
            formID: 0x42, editorID: "RecipeIronSword",
            components: [(0x0005_ACE4, 2)],
            conditions: [DialogueFixture.condition(functionIndex: 448, comparisonValue: 1)],
            createdObject: 0x0001_2EB7, workbenchKeyword: 0x0008_8105
        )
        let dump = try RecordTextDump.dump(record: ESMFixture.parseRecord(bytes), localized: false)
        #expect(dump.contains(
            "decoded COBJ: editorID RecipeIronSword, creates 00012EB7 x1, workbench 00088105"
        ))
        #expect(dump.contains("  components (1):\n    0005ACE4 x2"))
        #expect(dump.contains("  conditions (1):\n    HasPerk"))
    }

    @Test func dumpsFloraProduceAndWorkbench() throws {
        let flora = try Self.dump(
            "FLOR",
            InventoryFixture.formIDField("PFIG", 0x0007_7194)
                + ESMFixture.field("PFPC", Data([100, 100, 50, 0]))
        )
        #expect(flora.contains("produce 00077194, harvest sound NULL, seasons 100%/100%/50%/0%"))

        let forge = try Self.dump(
            "FURN",
            InventoryFixture.keywordFields([0x0008_8105]) + ESMFixture.field("WBDT", Data([2, 10]))
        )
        #expect(forge.contains("keywords [00088105], workbench smithingWeapon skill Smithing"))

        let skull = try Self.dump("TACT", InventoryFixture.formIDField("VNAM", 0x0001_3AD5))
        #expect(skull.contains("decoded TACT:"))
        #expect(skull.contains("voice type 00013AD5"))
    }
}
