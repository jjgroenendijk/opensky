// Synthetic ENCH decode coverage, plus the ARMO EITM link that lands with it.
// Every fixture is authored from the cited ENIT layout and contains no bytes
// from the game install.

import Foundation
@testable import opensky
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

enum EnchantmentFixture {
    /// The ENIT struct: cost, flags, cast type, amount, delivery, enchantment
    /// type, charge time, base enchantment, worn restrictions. Passing nil for
    /// `wornRestrictions` produces the 32-byte variant that omits it.
    static func enit(
        cost: Int32 = 0,
        flags: UInt32 = 0,
        castingType: UInt32 = 1,
        amount: Int32 = 0,
        delivery: UInt32 = 1,
        type: UInt32 = 6,
        chargeTime: Float = 0.5,
        baseEnchantment: UInt32 = 0,
        wornRestrictions: UInt32? = 0
    ) -> Data {
        var words: [UInt32] = [
            UInt32(bitPattern: cost),
            flags,
            castingType,
            UInt32(bitPattern: amount),
            delivery,
            type,
            chargeTime.bitPattern,
            baseEnchantment
        ]
        if let wornRestrictions {
            words.append(wornRestrictions)
        }
        return MagicEffectFixture.words(words)
    }

    /// One ENCH plus a weapon and a piece of armor that both name it, for the
    /// suites that exercise the EITM links.
    static func itemPlugin() throws -> ESMFile {
        let weapon = ESMFixture.record(
            "WEAP",
            formID: 0x500,
            data: ESMFixture.field("EDID", ESMFixture.zstring("TestEnchantedBlade"))
                + InventoryFixture.formIDField("EITM", 0x42)
                + ESMFixture.field("EAMT", chargeField(1500))
                + ESMFixture.field("DATA", InventoryFixture.weaponData(
                    value: 100,
                    weight: 12,
                    damage: 9
                ))
        )
        let plainWeapon = ESMFixture.record(
            "WEAP",
            formID: 0x600,
            data: ESMFixture.field("EDID", ESMFixture.zstring("TestPlainBlade"))
                + ESMFixture.field("DATA", InventoryFixture.weaponData(
                    value: 25,
                    weight: 9,
                    damage: 7
                ))
        )
        let armor = ESMFixture.record(
            "ARMO",
            formID: 0x700,
            data: ESMFixture.field("EDID", ESMFixture.zstring("TestEnchantedCuirass"))
                + InventoryFixture.formIDField("EITM", 0x42)
                + ESMFixture.field("DATA", InventoryFixture.valueWeightData(
                    value: 125,
                    weight: 30
                ))
        )
        return try SpellStoreFixture.plugin(
            records: SpellStoreFixture.effectRecords + [
                record(
                    formID: 0x42,
                    editorID: "TestEnchFire",
                    name: "Burning",
                    enit: enit(cost: 60, amount: 1500),
                    effects: [.init(0x50, magnitude: 25)]
                ),
                weapon,
                plainWeapon,
                armor
            ]
        )
    }

    /// EAMT, the weapon-side charge: a bare uint16.
    static func chargeField(_ value: UInt16) -> Data {
        var data = Data()
        data.appendUInt16(value)
        return data
    }

    /// The inspector context every ENCH dump assertion needs, over one plugin.
    static func inspectorContext(
        for file: ESMFile
    ) throws -> RecordTextDump.MagicInspectorContext {
        let index = RecordIndex(
            plugins: [("Base.esm", file)],
            recordTypes: ["MGEF", "SPEL", "SCRL", "ENCH", "FLST", "WEAP", "ARMO"]
        )
        let effects = MagicEffectStore(index: index)
        return RecordTextDump.MagicInspectorContext(
            keywordStore: KeywordStore(index: index),
            formListStore: FormListStore(index: index),
            magicEffectStore: effects,
            spellStore: SpellStore(index: index, effects: effects),
            enchantmentStore: EnchantmentStore(index: index, effects: effects),
            sourcePlugin: "Base.esm"
        )
    }

    static func record(
        formID: UInt32,
        editorID: String,
        name: String,
        enit: Data,
        effects: [SpellStoreFixture.EffectSpec] = []
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        fields += ESMFixture.field("FULL", ESMFixture.zstring(name))
        fields += ESMFixture.field("ENIT", enit)
        for effect in effects {
            fields += InventoryFixture.effectFields(
                effect: effect.effect,
                magnitude: effect.magnitude,
                area: 0,
                duration: effect.duration
            )
        }
        return ESMFixture.record("ENCH", formID: formID, data: fields)
    }
}
