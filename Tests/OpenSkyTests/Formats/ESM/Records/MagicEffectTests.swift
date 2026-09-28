// Synthetic MGEF decode coverage. Fixtures are authored from the cited
// 152-byte layout and contain no bytes from the game install.

import Foundation
@testable import OpenSky
@testable import OpenSkyFormats
import Testing

struct MagicEffectTests {
    @Test
    func decodesIdentityDataLinksAndLists() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("TestDamageHealth"))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Damage Health"))
        fields += ESMFixture.field("KSIZ", MagicEffectFixture.words([1]))
        fields += ESMFixture.field("KWDA", MagicEffectFixture.words([0x20]))
        fields += ESMFixture.field("DATA", MagicEffectFixture.data())
        fields += ESMFixture.field("ESCE", MagicEffectFixture.words([0x30]))
        fields += ESMFixture.field("SNDD", MagicEffectFixture.words([3, 0x40, 5, 0x41]))
        fields += ESMFixture.field("DNAM", ESMFixture.zstring("Deals <mag> damage."))
        fields += ESMFixture.field("CTDA", Data(count: 32))
        fields += ESMFixture.field("ZZZZ", Data([1]))
        let effect = try MagicEffect(
            record: MagicEffectFixture.record(type: "MGEF", formID: 0x10, fields: fields),
            localized: false
        )

        #expect(effect.formID == FormID(0x10))
        #expect(effect.editorID == "TestDamageHealth")
        #expect(effect.name == .inline("Damage Health"))
        #expect(effect.description == .inline("Deals <mag> damage."))
        #expect(effect.keywords.keywords == [FormID(0x20)])
        #expect(effect.counterEffects == [FormID(0x30)])
        #expect(effect.sounds == [
            MagicEffectSound(kind: 3, descriptor: FormID(0x40)),
            MagicEffectSound(kind: 5, descriptor: FormID(0x41))
        ])
        #expect(effect.conditions.conditions.count == 1)
        #expect(effect.skipped.counts[.unknownField("ZZZZ")] == 1)

        let data = try #require(effect.data)
        #expect(data.flags.contains(.hostile))
        #expect(data.baseCost == 12.5)
        #expect(data.associatedItem == FormID(0x100))
        #expect(data.magicSkill == 20)
        #expect(data.resistanceActorValue == 44)
        #expect(data.counterEffectCount == 0)
        #expect(data.archetype == .valueModifier)
        #expect(data.relatedActorValue == 24)
        #expect(data.projectile == FormID(0x200))
        #expect(data.explosion == FormID(0x201))
        #expect(data.castingType == .fireAndForget)
        #expect(data.delivery == .aimed)
        #expect(data.impactData == FormID(0x204))
        #expect(data.dualCastArt == FormID(0x205))
        #expect(data.equipAbility == FormID(0x209))
        #expect(data.unknownEnumCount == 0)
    }

    @Test
    func rejectsWrongTypeButToleratesTruncatedData() throws {
        #expect(throws: ESMError.self) {
            _ = try MagicEffect(
                record: MagicEffectFixture.record(type: "SPEL", fields: Data()),
                localized: false
            )
        }
        let record = try MagicEffectFixture.record(
            type: "MGEF",
            fields: ESMFixture.field("DATA", Data(count: 151))
        )
        let effect = try MagicEffect(record: record, localized: false)
        #expect(effect.data == nil)
        #expect(effect.skipped.counts[.malformedField("DATA")] == 1)
    }

    @Test
    func unknownEnumsSurviveDecode() throws {
        let record = try MagicEffectFixture.record(
            type: "MGEF",
            fields: ESMFixture.field(
                "DATA",
                MagicEffectFixture.data(archetype: 70, castingType: 80, delivery: 90)
            )
        )
        let data = try #require(try MagicEffect(record: record, localized: false).data)
        #expect(data.archetype == .unknown(raw: 70))
        #expect(data.castingType == .unknown(raw: 80))
        #expect(data.delivery == .unknown(raw: 90))
        #expect(data.unknownEnumCount == 3)
    }

    @Test
    func emptySoundListIsValid() throws {
        let effect = try MagicEffect(
            record: MagicEffectFixture.record(
                type: "MGEF",
                fields: ESMFixture.field("DATA", MagicEffectFixture.data())
                    + ESMFixture.field("SNDD", Data())
            ),
            localized: false
        )
        #expect(effect.sounds.isEmpty)
        #expect(effect.skipped.counts[.malformedField("SNDD")] == nil)
    }

    @Test
    func textDumpNamesActorValuesAndCoreSemantics() throws {
        let record = try MagicEffectFixture.record(
            type: "MGEF",
            fields: ESMFixture.field("EDID", ESMFixture.zstring("TestEffect"))
                + ESMFixture.field("FULL", ESMFixture.zstring("Test Effect"))
                + ESMFixture.field("DATA", MagicEffectFixture.data())
        )
        let dump = RecordTextDump.dump(record: record, localized: false)
        #expect(dump.contains("decoded MGEF: editorID TestEffect"))
        #expect(dump.contains("archetype value modifier"))
        #expect(dump.contains("casting fire and forget"))
        #expect(dump.contains("delivery aimed"))
        #expect(dump.contains("related actor value Health"))
        #expect(dump.contains("resistance Resist Magic"))
    }
}
