// Synthetic MGEF decode coverage. Fixtures are authored from the cited
// 152-byte layout and contain no bytes from the game install.

import Foundation
@testable import opensky
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

enum MagicEffectFixture {
    static func data(
        archetype: UInt32 = 0,
        castingType: UInt32 = 1,
        delivery: UInt32 = 2,
        baseCost: Float = 12.5
    ) -> Data {
        words([
            MagicEffectFlags.hostile.rawValue, baseCost.bitPattern, 0x100, 20, 44, 0,
            0x101, Float(0.5).bitPattern, 0x102, 0x103, 25, 10,
            Float(0.75).bitPattern, Float(1.25).bitPattern, Float(2).bitPattern,
            Float(0.4).bitPattern, archetype, 24, 0x200, 0x201, castingType, delivery, 25,
            0x202, 0x203, 0x204, Float(1.5).bitPattern, 0x205, Float(2.5).bitPattern,
            0x206, 0x207, 0x208, 0x209, 0x20A, 0x20B, 1,
            Float(50).bitPattern, Float(1).bitPattern
        ])
    }

    static func record(type: String, formID: UInt32 = 0, fields: Data) throws -> ESMRecord {
        let file = try ESMFile(
            data: ESMFixture.tes4()
                + ESMFixture.topGroup(
                    type,
                    contents: ESMFixture.record(type, formID: formID, data: fields)
                )
        )
        guard let group = file.topGroups.first else {
            throw ESMError.malformed("fixture has no top group")
        }
        guard let child = try group.children().first else {
            throw ESMError.malformed("fixture group has no child")
        }
        guard case let .record(record) = child else {
            throw ESMError.malformed("fixture child is not a record")
        }
        return record
    }

    static func words(_ values: [UInt32]) -> Data {
        var data = Data()
        for value in values {
            data.appendUInt32(value)
        }
        return data
    }
}
