// ALCH and INGR decoders plus the shared EFID/EFIT/CTDA effect run, over
// synthetic InventoryFixture records. Layout: docs/formats/item-records.md.

import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsESM
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct IngestibleRecordTests {
    /// ALCH is the family whose DATA is a bare weight, with the gold value in
    /// ENIT; both still land in the same engine-level `itemValue`.
    @Test func decodesIngestibleWithEffects() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("PotionHealth"))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Potion of Healing"))
        var weight = Data()
        weight.appendUInt32(Float(0.5).bitPattern)
        fields += ESMFixture.field("DATA", weight)
        fields += ESMFixture.field(
            "ENIT", InventoryFixture.enitData(value: 36, flags: 0x10000, addictionChance: 0.25)
        )
        fields += InventoryFixture.effectFields(
            effect: 0x0003_EAF3, magnitude: 5, area: 0, duration: 0
        )
        fields += InventoryFixture.effectFields(
            effect: 0x0003_EAF4, magnitude: 2, area: 1, duration: 10
        )
        let item = try Ingestible(
            record: InventoryFixture.record(
                ESMFixture.record("ALCH", formID: 0x33, data: fields)
            ),
            localized: false
        )
        #expect(item.itemValue == ItemValue(value: 36, weight: 0.5))
        #expect(item.flags == [.medicine])
        #expect(item.addiction == nil)
        #expect(item.addictionChance == 0.25)
        #expect(item.consumeSound == FormID(0x0002_0000))
        #expect(item.effects.count == 2)
        #expect(item.effects[0].effect == FormID(0x0003_EAF3))
        #expect(item.effects[0].magnitude == 5)
        #expect(item.effects[1].duration == 10)
        #expect(item.effects[1].area == 1)
    }

    @Test func rejectsWrongTypeAndTruncatedENIT() {
        #expect(throws: ESMError.self) {
            _ = try Ingestible(
                record: InventoryFixture.record(ESMFixture.record("INGR", data: Data())),
                localized: false
            )
        }
        #expect(throws: ESMError.self) {
            _ = try Ingestible(
                record: InventoryFixture.record(
                    ESMFixture.record("ALCH", data: ESMFixture.field("ENIT", Data(count: 19)))
                ),
                localized: false
            )
        }
    }

    /// The ENIT flag bits docs/formats/item-records.md lists.
    @Test func flagBitsMatchTheDocumentedList() {
        let documented: [(Ingestible.Flags, UInt32)] = [
            (.noAutoCalc, 0x00001), (.food, 0x00002), (.medicine, 0x10000), (.poison, 0x20000)
        ]
        for (flag, bits) in documented {
            #expect(flag.rawValue == bits)
        }
    }

    @Test func emptyRecordDecodesToDefaults() throws {
        let item = try Ingestible(
            record: InventoryFixture.record(ESMFixture.record("ALCH", data: Data())),
            localized: false
        )
        #expect(item.itemValue == .zero)
        #expect(item.effects.isEmpty)
    }
}

@Suite(.tags(.parser))
struct IngredientRecordTests {
    @Test func decodesIngredientWithConditionedEffect() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("MountainFlower"))
        fields += ESMFixture.field(
            "DATA", InventoryFixture.valueWeightData(value: 2, weight: 0.1)
        )
        var enit = Data()
        enit.appendUInt32(UInt32(bitPattern: Int32(15)))
        enit.appendUInt32(0x0000_0100)
        fields += ESMFixture.field("ENIT", enit)
        fields += InventoryFixture.effectFields(
            effect: 0x0003_EAF3, magnitude: 5, area: 0, duration: 0
        )
        fields += ESMFixture.field("CTDA", Data(count: 32))
        let ingredient = try Ingredient(
            record: InventoryFixture.record(
                ESMFixture.record("INGR", formID: 0x44, data: fields)
            ),
            localized: false
        )
        #expect(ingredient.itemValue == ItemValue(value: 2, weight: 0.1))
        #expect(ingredient.autoCalcValue == 15)
        #expect(ingredient.flags == [.referencesPersist])
        #expect(ingredient.effects.count == 1)
        #expect(ingredient.effects[0].conditions.conditions.count == 1)
    }

    @Test func rejectsWrongTypeAndTruncatedData() {
        #expect(throws: ESMError.self) {
            _ = try Ingredient(
                record: InventoryFixture.record(ESMFixture.record("ALCH", data: Data())),
                localized: false
            )
        }
        #expect(throws: ESMError.self) {
            _ = try Ingredient(
                record: InventoryFixture.record(
                    ESMFixture.record("INGR", data: ESMFixture.field("DATA", Data(count: 4)))
                ),
                localized: false
            )
        }
    }

    @Test func emptyRecordDecodesToDefaults() throws {
        let ingredient = try Ingredient(
            record: InventoryFixture.record(ESMFixture.record("INGR", data: Data())),
            localized: false
        )
        #expect(ingredient.effects.isEmpty)
        #expect(ingredient.itemValue == .zero)
    }

    /// An EFIT with no EFID before it has no effect to attach to, and an EFID
    /// whose EFIT never arrives still yields the MGEF link.
    @Test func effectRunToleratesMissingHalves() throws {
        var fields = ESMFixture.field("EFIT", Data(count: 12)) // orphan
        fields += InventoryFixture.formIDField("EFID", 0x0AA)
        let ingredient = try Ingredient(
            record: InventoryFixture.record(ESMFixture.record("INGR", data: fields)),
            localized: false
        )
        #expect(ingredient.effects.count == 1)
        #expect(ingredient.effects[0].effect == FormID(0x0AA))
        #expect(ingredient.effects[0].magnitude == 0)
    }

    /// The INGR ENIT flag bits docs/formats/item-records.md lists.
    @Test func flagBitsMatchTheDocumentedList() {
        let documented: [(Ingredient.Flags, UInt32)] = [
            (.noAutoCalc, 0x001), (.food, 0x002), (.referencesPersist, 0x100)
        ]
        for (flag, bits) in documented {
            #expect(flag.rawValue == bits)
        }
    }
}
