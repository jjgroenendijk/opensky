// Synthetic ENCH decode coverage, plus the ARMO EITM link that lands with it.
// Every fixture is authored from the cited ENIT layout and contains no bytes
// from the game install.

import FormatsTestSupport
import Foundation
@testable import OpenSky
@testable import OpenSkyFormats
import Testing

struct EnchantmentTests {
    @Test
    func decodesIdentityEffectDataAndEffects() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("TestEnchFireDamage"))
        fields += ESMFixture.field("OBND", Data(count: 12))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Burning"))
        fields += ESMFixture.field("ENIT", EnchantmentFixture.enit(
            cost: 60,
            castingType: 1,
            amount: 1500,
            delivery: 1,
            type: 6,
            chargeTime: 0.75,
            baseEnchantment: 0x90,
            wornRestrictions: 0x91
        ))
        fields += InventoryFixture.effectFields(
            effect: 0x50,
            magnitude: 10,
            area: 0,
            duration: 0
        )
        fields += ESMFixture.field("CTDA", Data(count: 32))
        fields += ESMFixture.field("ZZZZ", Data([1]))
        let enchantment = try Enchantment(
            record: MagicEffectFixture.record(type: "ENCH", formID: 0x10, fields: fields),
            localized: false
        )

        #expect(enchantment.formID == FormID(0x10))
        #expect(enchantment.editorID == "TestEnchFireDamage")
        #expect(enchantment.name == .inline("Burning"))
        #expect(enchantment.bounds?.isEmpty == true)
        #expect(enchantment.skipped.counts[.unknownField("ZZZZ")] == 1)

        let data = try #require(enchantment.data)
        #expect(data.cost == 60)
        #expect(data.flags.isEmpty)
        #expect(data.usesAutoCalculatedCost)
        #expect(data.castingType == .fireAndForget)
        #expect(data.amount == 1500)
        #expect(data.delivery == .touch)
        #expect(data.type == .enchantment)
        #expect(data.chargeTime == 0.75)
        #expect(data.baseEnchantment == FormID(0x90))
        #expect(data.wornRestrictions == FormID(0x91))
        #expect(data.unknownEnumCount == 0)

        let effect = try #require(enchantment.effects.first)
        #expect(enchantment.effects.count == 1)
        #expect(effect.effect == FormID(0x50))
        #expect(effect.magnitude == 10)
        #expect(effect.conditions.conditions.count == 1)
    }

    /// The form-version-37 variant UESP documents: 32 bytes, worn restrictions
    /// omitted. Everything before that link still decodes.
    @Test
    func thirtyTwoByteVariantDropsOnlyTheWornRestrictionsLink() throws {
        let record = try MagicEffectFixture.record(
            type: "ENCH",
            fields: ESMFixture.field("ENIT", EnchantmentFixture.enit(
                cost: 42,
                baseEnchantment: 0x90,
                wornRestrictions: nil
            ))
        )
        let data = try #require(try Enchantment(record: record, localized: false).data)
        #expect(data.cost == 42)
        #expect(data.baseEnchantment == FormID(0x90))
        #expect(data.wornRestrictions == nil)
    }

    @Test
    func rejectsWrongTypeButKeepsEffectsWhenEffectDataIsTruncated() throws {
        #expect(throws: ESMError.self) {
            _ = try Enchantment(
                record: MagicEffectFixture.record(type: "SPEL", fields: Data()),
                localized: false
            )
        }
        let record = try MagicEffectFixture.record(
            type: "ENCH",
            fields: ESMFixture.field("ENIT", Data(count: 31))
                + InventoryFixture.effectFields(effect: 9, magnitude: 1, area: 0, duration: 0)
        )
        let enchantment = try Enchantment(record: record, localized: false)
        #expect(enchantment.data == nil)
        #expect(enchantment.skipped.counts[.malformedField("ENIT")] == 1)
        #expect(enchantment.effects.map(\.effect) == [FormID(9)])
    }

    @Test
    func nullLinksAndUnknownEnumValuesSurviveDecode() throws {
        let record = try MagicEffectFixture.record(
            type: "ENCH",
            fields: ESMFixture.field("ENIT", EnchantmentFixture.enit(
                flags: EnchantmentFlags.manualCostCalc.rawValue
                    | EnchantmentFlags.extendDurationOnRecast.rawValue,
                castingType: 80,
                delivery: 90,
                type: 7,
                baseEnchantment: 0,
                wornRestrictions: 0
            ))
        )
        let data = try #require(try Enchantment(record: record, localized: false).data)
        #expect(data.flags == [.manualCostCalc, .extendDurationOnRecast])
        #expect(!data.usesAutoCalculatedCost)
        #expect(data.castingType == .unknown(raw: 80))
        #expect(data.delivery == .unknown(raw: 90))
        #expect(data.type == .unknown(raw: 7))
        #expect(data.unknownEnumCount == 3)
        #expect(data.baseEnchantment == nil)
        #expect(data.wornRestrictions == nil)
    }

    /// ARMO gained its EITM link with this issue. There is no armor-side
    /// charge field: only WEAP's link carries EAMT.
    @Test
    func armorDecodesItsEnchantmentLink() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("ArmorEnchanted"))
        fields += InventoryFixture.formIDField("EITM", 0x0A)
        fields += ESMFixture.field(
            "DATA",
            InventoryFixture.valueWeightData(value: 125, weight: 30)
        )
        let record = try MagicEffectFixture.record(type: "ARMO", formID: 0x20, fields: fields)
        let armor = try Armor(record: record, localized: false)
        #expect(armor.editorID == "ArmorEnchanted")
        #expect(armor.enchantment == FormID(0x0A))
        #expect(armor.itemValue == ItemValue(value: 125, weight: 30))

        let plain = try Armor(
            record: MagicEffectFixture.record(
                type: "ARMO",
                formID: 0x21,
                fields: ESMFixture.field("EDID", ESMFixture.zstring("ArmorPlain"))
            ),
            localized: false
        )
        #expect(plain.enchantment == nil)
    }
}
