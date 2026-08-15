// Synthetic SPEL and SCRL decode coverage. Every fixture is authored from the
// cited 36-byte SPIT layout and contains no bytes from the game install.

import Foundation
@testable import opensky
import Testing

struct SpellTests {
    @Test
    func decodesIdentityCastingHeaderAndEffects() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("TestFirebolt"))
        fields += ESMFixture.field("OBND", Data(count: 12))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Firebolt"))
        fields += ESMFixture.field("KSIZ", MagicEffectFixture.words([1]))
        fields += ESMFixture.field("KWDA", MagicEffectFixture.words([0x20]))
        fields += ESMFixture.field("MDOB", MagicEffectFixture.words([0x30]))
        fields += ESMFixture.field("ETYP", MagicEffectFixture.words([0x31]))
        fields += ESMFixture.field("DESC", ESMFixture.zstring("A bolt of fire."))
        fields += ESMFixture.field("SPIT", SpellFixture.spit(
            baseCost: 41,
            flags: SpellFlags.pcStartSpell.rawValue,
            type: 0,
            chargeTime: 0.5,
            range: 300,
            halfCostPerk: 0x40
        ))
        fields += InventoryFixture.effectFields(
            effect: 0x50,
            magnitude: 25,
            area: 0,
            duration: 0
        )
        fields += ESMFixture.field("CTDA", Data(count: 32))
        fields += ESMFixture.field("ZZZZ", Data([1]))
        let spell = try Spell(
            record: MagicEffectFixture.record(type: "SPEL", formID: 0x10, fields: fields),
            localized: false
        )

        #expect(spell.formID == FormID(0x10))
        #expect(spell.editorID == "TestFirebolt")
        #expect(spell.name == .inline("Firebolt"))
        #expect(spell.header.description == .inline("A bolt of fire."))
        #expect(spell.header.fields.keywords.keywords == [FormID(0x20)])
        #expect(spell.header.menuDisplayObject == FormID(0x30))
        #expect(spell.header.equipType == FormID(0x31))
        #expect(spell.header.fields.bounds?.isEmpty == true)
        #expect(spell.skipped.counts[.unknownField("ZZZZ")] == 1)

        let data = try #require(spell.data)
        #expect(data.baseCost == 41)
        #expect(data.flags == [.pcStartSpell])
        #expect(data.usesAutoCalculatedCost)
        #expect(data.type == .spell)
        #expect(data.chargeTime == 0.5)
        #expect(data.castingType == .fireAndForget)
        #expect(data.delivery == .aimed)
        #expect(data.range == 300)
        #expect(data.halfCostPerk == FormID(0x40))
        #expect(data.unknownEnumCount == 0)

        let effect = try #require(spell.effects.first)
        #expect(spell.effects.count == 1)
        #expect(effect.effect == FormID(0x50))
        #expect(effect.magnitude == 25)
        #expect(effect.duration == 0)
        #expect(effect.conditions.conditions.count == 1)
    }

    @Test
    func rejectsWrongTypeButKeepsEffectsWhenSpellItemDataIsTruncated() throws {
        #expect(throws: ESMError.self) {
            _ = try Spell(
                record: MagicEffectFixture.record(type: "SCRL", fields: Data()),
                localized: false
            )
        }
        #expect(throws: ESMError.self) {
            _ = try Scroll(
                record: MagicEffectFixture.record(type: "SPEL", fields: Data()),
                localized: false
            )
        }
        let record = try MagicEffectFixture.record(
            type: "SPEL",
            fields: ESMFixture.field("SPIT", Data(count: 35))
                + InventoryFixture.effectFields(effect: 9, magnitude: 1, area: 0, duration: 0)
        )
        let spell = try Spell(record: record, localized: false)
        #expect(spell.data == nil)
        #expect(spell.skipped.counts[.malformedField("SPIT")] == 1)
        #expect(spell.effects.map(\.effect) == [FormID(9)])
    }

    @Test
    func unknownSpellTypeAndCastingValuesSurviveDecode() throws {
        let record = try MagicEffectFixture.record(
            type: "SPEL",
            fields: ESMFixture.field(
                "SPIT",
                SpellFixture.spit(type: 77, castingType: 80, delivery: 90)
            )
        )
        let data = try #require(try Spell(record: record, localized: false).data)
        #expect(data.type == .unknown(raw: 77))
        #expect(data.castingType == .unknown(raw: 80))
        #expect(data.delivery == .unknown(raw: 90))
        #expect(data.unknownEnumCount == 3)
    }

    @Test
    func scrollDecodesItemFieldsBesideTheCastingHeader() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("TestScrollFirebolt"))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Scroll of Firebolt"))
        fields += ESMFixture.field("MODL", ESMFixture.zstring("Clutter\\Scroll01.nif"))
        fields += ESMFixture.field("YNAM", MagicEffectFixture.words([0x60]))
        fields += ESMFixture.field("ZNAM", MagicEffectFixture.words([0x61]))
        fields += ESMFixture.field("DATA", InventoryFixture.valueWeightData(
            value: 27,
            weight: 0.5
        ))
        // Scrolls write casting type 3, which xEdit names "Scroll".
        fields += ESMFixture.field("SPIT", SpellFixture.spit(castingType: 3, delivery: 2))
        fields += InventoryFixture.effectFields(
            effect: 0x50,
            magnitude: 25,
            area: 0,
            duration: 0
        )
        let scroll = try Scroll(
            record: MagicEffectFixture.record(type: "SCRL", formID: 0x11, fields: fields),
            localized: false
        )

        #expect(scroll.editorID == "TestScrollFirebolt")
        #expect(scroll.name == .inline("Scroll of Firebolt"))
        #expect(scroll.header.fields.modelPath == "Clutter\\Scroll01.nif")
        #expect(scroll.header.fields.pickupSound == FormID(0x60))
        #expect(scroll.header.fields.dropSound == FormID(0x61))
        #expect(scroll.itemValue == ItemValue(value: 27, weight: 0.5))
        #expect(scroll.data?.castingType == .scroll)
        #expect(scroll.data?.unknownEnumCount == 0)
        #expect(scroll.effects.count == 1)
        #expect(scroll.skipped.total == 0)
    }

    @Test
    func malformedScrollItemDataIsTalliedWithoutLosingTheRecord() throws {
        let record = try MagicEffectFixture.record(
            type: "SCRL",
            fields: ESMFixture.field("EDID", ESMFixture.zstring("BrokenScroll"))
                + ESMFixture.field("DATA", Data(count: 7))
                + ESMFixture.field("SPIT", SpellFixture.spit(castingType: 3))
        )
        let scroll = try Scroll(record: record, localized: false)
        #expect(scroll.editorID == "BrokenScroll")
        #expect(scroll.itemValue == ItemValue.zero)
        #expect(scroll.skipped.counts[.malformedField("DATA")] == 1)
        #expect(scroll.data != nil)
    }

    /// The formula UESP documents on the SPEL page:
    /// `base cost * (magnitude * duration / 10) ^ 1.1`, with a magnitude below
    /// 1 counted as 1 and a duration of 0 — or any concentration duration —
    /// counted as 10. Expected values are hand-computed from that expression.
    @Test
    func effectCostFollowsTheDocumentedCurve() {
        let instant = SpellCost.effectCost(
            baseCost: 10,
            magnitude: 25,
            duration: 0,
            castingType: .fireAndForget
        )
        #expect(abs(instant - 344.932_4) < 0.01)

        let timed = SpellCost.effectCost(
            baseCost: 2.5,
            magnitude: 5,
            duration: 60,
            castingType: .fireAndForget
        )
        #expect(abs(timed - 105.383_7) < 0.01)

        // A concentration spell is quoted over the same ten-second window.
        let concentration = SpellCost.effectCost(
            baseCost: 3,
            magnitude: 8,
            duration: 60,
            castingType: .concentration
        )
        #expect(abs(concentration - 29.547_5) < 0.01)

        // Magnitude below 1 is floored to 1, so the cost is the base cost.
        let floored = SpellCost.effectCost(
            baseCost: 10,
            magnitude: 0.5,
            duration: 0,
            castingType: .fireAndForget
        )
        #expect(abs(floored - 10) < 0.001)

        // An effect with no base cost contributes nothing.
        #expect(SpellCost.effectCost(
            baseCost: 0,
            magnitude: 25,
            duration: 0,
            castingType: .fireAndForget
        ) == 0)
    }
}

enum SpellFixture {
    /// The 36-byte SPIT struct: base cost, flags, type, charge time, casting
    /// type, delivery, cast duration, range, half-cost PERK.
    static func spit(
        baseCost: UInt32 = 0,
        flags: UInt32 = 0,
        type: UInt32 = 0,
        chargeTime: Float = 0.5,
        castingType: UInt32 = 1,
        delivery: UInt32 = 2,
        castDuration: Float = 0,
        range: Float = 0,
        halfCostPerk: UInt32 = 0
    ) -> Data {
        MagicEffectFixture.words([
            baseCost,
            flags,
            type,
            chargeTime.bitPattern,
            castingType,
            delivery,
            castDuration.bitPattern,
            range.bitPattern,
            halfCostPerk
        ])
    }
}
