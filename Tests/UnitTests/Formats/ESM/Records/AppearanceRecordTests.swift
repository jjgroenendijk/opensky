// Appearance record decoder tests (RACE, ARMO, ARMA, OTFT, BodyTemplate) over
// synthetic in-code records (ESMFixture) — never extracted game files (AGENTS.md
// "Legal & IP boundary"). Layouts: UESP "Skyrim Mod:Mod File Format" per-record
// pages; biped slot bits from NifTools nif.xml BSDismemberBodyPartType.

import Foundation
@testable import opensky
import Testing

struct AppearanceRecordDecodeTests {
    // MARK: - HDPT

    @Test func headPartPairsNamedMorphKindsWithPaths() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("MaleHeadNord"))
        fields += uint32Field("NAM0", 0)
        fields += ESMFixture.field("NAM1", ESMFixture.zstring("maleheadraces.tri"))
        fields += uint32Field("NAM0", 1)
        fields += ESMFixture.field("NAM1", ESMFixture.zstring("malehead.tri"))
        fields += uint32Field("NAM0", 2)
        fields += ESMFixture.field("NAM1", ESMFixture.zstring("maleheadchargen.tri"))
        let part = try HeadPart(record: record(
            ESMFixture.record("HDPT", formID: 0x5162F, data: fields)
        ))

        #expect(part.editorID == "MaleHeadNord")
        #expect(part.expressionMorphPath == "malehead.tri")
        #expect(part.morphPaths.map(\.kind) == [.race, .expression, .chargen])
    }

    @Test func headPartIgnoresNam1WithoutATypeAndUnknownTypes() throws {
        var fields = ESMFixture.field("NAM1", ESMFixture.zstring("orphan.tri"))
        fields += uint32Field("NAM0", 99)
        fields += ESMFixture.field("NAM1", ESMFixture.zstring("future.tri"))
        let part = try HeadPart(record: record(
            ESMFixture.record("HDPT", formID: 1, data: fields)
        ))
        #expect(part.morphPaths.isEmpty)
    }

    // MARK: - BodyTemplate / BodySlots

    @Test func bod2DecodesSlotsAndArmorType() throws {
        // Bits 0/2/7 -> slots 30 head, 32 body, 37 feet; armor type 1 = heavy.
        var data = Data()
        data.appendUInt32(0b1000_0101)
        data.appendUInt32(1)
        let template = try BodyTemplate(bod2: ESMField(type: "BOD2", data: data))
        #expect(template.slots == [.head, .body, .feet])
        #expect(template.armorType == .heavy)
    }

    @Test func bodt12ByteDecodesSlotsSkippingGeneralFlags() throws {
        // uint32 slots, uint32 general flags (ignored), uint32 armor type.
        var data = Data()
        data.appendUInt32(0b0100) // slot 32 body
        data.appendUInt32(0xDEAD_BEEF) // general flags — skipped
        data.appendUInt32(2) // clothing
        let template = try BodyTemplate(bodt: ESMField(type: "BODT", data: data))
        #expect(template.slots == [.body])
        #expect(template.armorType == .clothing)
    }

    @Test func bodt8ByteDecodesSlotsAndLeavesArmorTypeNil() throws {
        // 8-byte legacy form: trailing layout ambiguous -> armor type nil.
        var data = Data()
        data.appendUInt32(0b0010) // slot 31 hair
        data.appendUInt32(0)
        let template = try BodyTemplate(bodt: ESMField(type: "BODT", data: data))
        #expect(template.slots == [.hair])
        #expect(template.armorType == nil)
    }

    @Test func bodyTemplateRejectsTruncatedField() throws {
        #expect(throws: ESMError.self) {
            _ = try BodyTemplate(bod2: ESMField(type: "BOD2", data: Data(count: 2)))
        }
    }

    @Test func bodyTemplateIgnoresUnknownArmorType() throws {
        var data = Data()
        data.appendUInt32(1)
        data.appendUInt32(99) // not a defined ArmorType
        let template = try BodyTemplate(bod2: ESMField(type: "BOD2", data: data))
        #expect(template.armorType == nil)
    }

    @Test func bodySlotsOverlapDetectsSharedSlot() {
        #expect(BodySlots([.body, .feet]).overlaps([.feet, .hands]))
        #expect(!BodySlots([.body, .feet]).overlaps([.hands, .head]))
    }

    // MARK: - RACE

    @Test func decodesRaceAppearance() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("NordRace"))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Nord"))
        fields += formIDField("WNAM", 0x0001_3746)
        var bod2 = Data()
        bod2.appendUInt32(0b0100) // body
        bod2.appendUInt32(2)
        fields += ESMFixture.field("BOD2", bod2)
        // DATA: 0x20 stat bytes then the uint32 flags word (UESP RACE).
        var raceData = Data(count: 0x20)
        raceData.appendUInt32(0x3) // playable + FaceGen head
        fields += ESMFixture.field("DATA", raceData)
        fields += ESMFixture.field("MNAM", Data())
        fields += ESMFixture.field("ANAM", ESMFixture.zstring("actors\\character\\male.nif"))
        fields += ESMFixture.field("MODT", Data(count: 12)) // skipped
        fields += ESMFixture.field("FNAM", Data())
        fields += ESMFixture.field("ANAM", ESMFixture.zstring("actors\\character\\female.nif"))
        let race = try Race(
            record: record(ESMFixture.record("RACE", formID: 0x1234, data: fields)),
            localized: false
        )
        #expect(race.formID == FormID(0x1234))
        #expect(race.editorID == "NordRace")
        #expect(race.name == .inline("Nord"))
        #expect(race.defaultSkin == FormID(0x0001_3746))
        #expect(race.bodyTemplate?.slots == [.body])
        #expect(race.flags == [.playable, .faceGenHead])
        #expect(race.maleSkeletonPath == "actors\\character\\male.nif")
        #expect(race.femaleSkeletonPath == "actors\\character\\female.nif")
    }

    @Test func raceFlagsEmptyWhenDataTruncated() throws {
        // A DATA too short to reach the flags word decodes as no flags.
        let fields = ESMFixture.field("DATA", Data(count: 0x10))
        let race = try Race(
            record: record(ESMFixture.record("RACE", formID: 1, data: fields)),
            localized: false
        )
        #expect(race.flags.isEmpty)
    }

    @Test func raceSkeletonPathsNilWhenAbsent() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("AlduinRace"))
        let race = try Race(
            record: record(ESMFixture.record("RACE", formID: 1, data: fields)),
            localized: false
        )
        #expect(race.maleSkeletonPath == nil)
        #expect(race.femaleSkeletonPath == nil)
        #expect(race.bodyTemplate == nil)
        #expect(race.defaultSkin == nil)
    }

    @Test func raceIgnoresLaterMarkerBlocksWithoutAnam() throws {
        // Skeleton block sets both paths; a later MNAM block carries MODL, not
        // ANAM, so the skeleton paths must stay put.
        var fields = ESMFixture.field("MNAM", Data())
        fields += ESMFixture.field("ANAM", ESMFixture.zstring("skel_m.nif"))
        fields += ESMFixture.field("FNAM", Data())
        fields += ESMFixture.field("ANAM", ESMFixture.zstring("skel_f.nif"))
        fields += ESMFixture.field("MNAM", Data()) // start of male body-model block
        fields += ESMFixture.field("MODL", ESMFixture.zstring("body.nif"))
        let race = try Race(
            record: record(ESMFixture.record("RACE", formID: 1, data: fields)),
            localized: false
        )
        #expect(race.maleSkeletonPath == "skel_m.nif")
        #expect(race.femaleSkeletonPath == "skel_f.nif")
    }

    @Test func raceDecodesGenderedFaceGenHeadPartLists() throws {
        var fields = ESMFixture.field("MNAM", Data())
        fields += ESMFixture.field("ANAM", ESMFixture.zstring("skel_m.nif"))
        fields += ESMFixture.field("FNAM", Data())
        fields += ESMFixture.field("ANAM", ESMFixture.zstring("skel_f.nif"))
        fields += ESMFixture.field("NAM0", Data())
        fields += ESMFixture.field("MNAM", Data())
        fields += uint32Field("HEAD", 0x10)
        fields += uint32Field("HEAD", 0x11)
        fields += ESMFixture.field("NAM0", Data())
        fields += ESMFixture.field("FNAM", Data())
        fields += uint32Field("HEAD", 0x20)
        let race = try Race(
            record: record(ESMFixture.record("RACE", formID: 1, data: fields)),
            localized: false
        )

        #expect(race.maleHeadParts == [FormID(0x10), FormID(0x11)])
        #expect(race.femaleHeadParts == [FormID(0x20)])
        #expect(race.maleSkeletonPath == "skel_m.nif")
        #expect(race.femaleSkeletonPath == "skel_f.nif")
    }

    @Test func raceRejectsOtherRecordTypes() throws {
        let bytes = ESMFixture.record("ARMO", formID: 1, data: Data())
        #expect(throws: ESMError.self) {
            _ = try Race(record: record(bytes), localized: false)
        }
    }

    // MARK: - ARMO

    @Test func decodesArmorAppearance() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("ArmorIronCuirass"))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Iron Armor"))
        fields += formIDField("RNAM", 0x19)
        var bodt = Data()
        bodt.appendUInt32(0b0100) // body
        bodt.appendUInt32(0)
        bodt.appendUInt32(1) // heavy
        fields += ESMFixture.field("BODT", bodt)
        fields += ESMFixture.field("MOD2", ESMFixture.zstring("armor\\iron\\ground.nif")) // skipped
        fields += formIDField("MODL", 0x0001_A1A1)
        fields += formIDField("MODL", 0x0001_B2B2)
        let armor = try Armor(
            record: record(ESMFixture.record("ARMO", formID: 0x5000, data: fields)),
            localized: false
        )
        #expect(armor.formID == FormID(0x5000))
        #expect(armor.editorID == "ArmorIronCuirass")
        #expect(armor.name == .inline("Iron Armor"))
        #expect(armor.race == FormID(0x19))
        #expect(armor.bodyTemplate?.slots == [.body])
        #expect(armor.bodyTemplate?.armorType == .heavy)
        #expect(armor.armatures == [FormID(0x0001_A1A1), FormID(0x0001_B2B2)])
    }

    @Test func armorSkipsNonFormIDModl() throws {
        // A path-shaped MODL (not 4 bytes) is skipped, not misread.
        var fields = ESMFixture.field("MODL", ESMFixture.zstring("armor\\model.nif"))
        fields += formIDField("MODL", 0x0001_C3C3)
        let armor = try Armor(
            record: record(ESMFixture.record("ARMO", formID: 1, data: fields)),
            localized: false
        )
        #expect(armor.armatures == [FormID(0x0001_C3C3)])
    }

    @Test func armorEmptyWhenFieldsAbsent() throws {
        let armor = try Armor(
            record: record(ESMFixture.record("ARMO", formID: 1, data: Data())),
            localized: false
        )
        #expect(armor.armatures.isEmpty)
        #expect(armor.race == nil)
        #expect(armor.bodyTemplate == nil)
    }

    @Test func armorRejectsOtherRecordTypes() throws {
        let bytes = ESMFixture.record("ARMA", formID: 1, data: Data())
        #expect(throws: ESMError.self) {
            _ = try Armor(record: record(bytes), localized: false)
        }
    }

    // MARK: - OTFT

    @Test func decodesOutfit() throws {
        var inam = Data()
        inam.appendUInt32(0x0001_F6F6)
        inam.appendUInt32(0x0002_0707)
        inam.appendUInt32(0x0002_1818)
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("FarmClothesOutfit"))
        fields += ESMFixture.field("INAM", inam)
        let outfit = try Outfit(
            record: record(ESMFixture.record("OTFT", formID: 0x7000, data: fields))
        )
        #expect(outfit.formID == FormID(0x7000))
        #expect(outfit.editorID == "FarmClothesOutfit")
        #expect(outfit.items == [
            FormID(0x0001_F6F6), FormID(0x0002_0707), FormID(0x0002_1818)
        ])
    }

    @Test func outfitEmptyWhenInamAbsent() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("EmptyOutfit"))
        let outfit = try Outfit(
            record: record(ESMFixture.record("OTFT", formID: 1, data: fields))
        )
        #expect(outfit.items.isEmpty)
    }

    @Test func outfitRejectsMisalignedInam() throws {
        let fields = ESMFixture.field("INAM", Data(count: 6)) // not a multiple of 4
        #expect(throws: ESMError.self) {
            _ = try Outfit(record: record(ESMFixture.record("OTFT", formID: 1, data: fields)))
        }
    }

    @Test func outfitRejectsOtherRecordTypes() throws {
        let bytes = ESMFixture.record("ARMO", formID: 1, data: Data())
        #expect(throws: ESMError.self) {
            _ = try Outfit(record: record(bytes))
        }
    }
}

// MARK: - Fixture helpers

/// Parses one synthetic record through the container walk.
private func record(_ bytes: Data) throws -> ESMRecord {
    let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
    guard case let .record(record)? = children.first else {
        throw ESMError.malformed("fixture did not produce a record")
    }
    return record
}

private func formIDField(_ type: String, _ value: UInt32) -> Data {
    uint32Field(type, value)
}

private func uint32Field(_ type: String, _ value: UInt32) -> Data {
    var data = Data()
    data.appendUInt32(value)
    return ESMFixture.field(type, data)
}
