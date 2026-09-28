// One synthetic plugin covering every inventory baseline source (issue #176).
// Built in code from the published record layouts — never extracted game files
// (AGENTS.md "Legal & IP boundary").
//
// The whole plugin is assembled and handed to `InventoryBaselineResolver
// .build(from:)` rather than the indexes being injected directly, so the tests
// exercise the same indexing path the engine uses.
//
// Form numbering, kept in one place because several suites assert against it:
//
//   0x00_000F  MISC Gold001        (vanilla gold's real form, weight 0)
//   0x00_0100  MISC Lockpick       (weight 0)
//   0x00_0200  WEAP IronSword      (weight 9, value 25; ETYP EitherHand)
//   0x00_0210  WEAP IronGreatsword (ETYP BothHands)
//   0x00_0300  ARMO IronCuirass    (weight 30, value 125; slot 32 body)
//   0x00_0400  ARMO IronHelmet     (weight 5, value 60; slot 30 head)
//   0x00_0410  ARMO LeatherCuirass (slot 32 body — contests IronCuirass)
//   0x00_0420  ARMO IronGauntlets  (slot 33 hands — contests nothing)
//   0x00_0500  EQUP RightHand      (leaf)
//   0x00_0510  EQUP LeftHand       (leaf)
//   0x00_0520  EQUP EitherHand     (parents left + right, use all 0)
//   0x00_0530  EQUP BothHands      (parents left + right, use all 1)
//   0x00_1000  LVLI single pick    -> IronSword at level 1, IronCuirass at 5
//   0x00_1010  LVLI useAll bundle  -> IronCuirass + IronHelmet
//   0x00_1020  LVLI self-referring -> itself, for the cycle guard
//   0x00_1030  LVLI empty
//   0x00_2000  OTFT               -> IronCuirass + the useAll bundle
//   0x00_2010  OTFT               -> the empty list only
//   0x00_3000  NPC_ Guard          (DOFT 0x2000)
//   0x00_3010  NPC_ template child (useInventory, TPLT 0x3000, DOFT 0x2010)
//   0x00_3020  NPC_ no outfit
//   0x00_4000  CONT Chest          (3 lockpicks, 1 gold, 1 single-pick LVLI)
//   0x00_4010  CONT LeveledChest   (the useAll bundle, twice over)
//   0x00_4020  CONT Empty

import Foundation
@testable import opensky

enum InventoryBaselineFixture {
    static let gold = FormID(0x0000_000F)
    static let lockpick = FormID(0x0000_0100)
    static let sword = FormID(0x0000_0200)
    static let greatsword = FormID(0x0000_0210)
    static let cuirass = FormID(0x0000_0300)
    static let helmet = FormID(0x0000_0400)
    static let leatherCuirass = FormID(0x0000_0410)
    static let gauntlets = FormID(0x0000_0420)

    static let rightHandSlot = FormID(0x0000_0500)
    static let leftHandSlot = FormID(0x0000_0510)
    static let eitherHandSlot = FormID(0x0000_0520)
    static let bothHandsSlot = FormID(0x0000_0530)

    static let singlePickList = FormID(0x0000_1000)
    static let bundleList = FormID(0x0000_1010)
    static let cyclicList = FormID(0x0000_1020)
    static let emptyList = FormID(0x0000_1030)

    static let guardOutfit = FormID(0x0000_2000)
    static let emptyOutfit = FormID(0x0000_2010)

    static let guardActor = FormID(0x0000_3000)
    static let templatedActor = FormID(0x0000_3010)
    static let outfitlessActor = FormID(0x0000_3020)

    static let chest = FormID(0x0000_4000)
    static let leveledChest = FormID(0x0000_4010)
    static let emptyChest = FormID(0x0000_4020)

    static func resolver() throws -> InventoryBaselineResolver {
        try InventoryBaselineResolver.build(from: ESMFile(data: pluginBytes()))
    }

    static func pluginBytes() -> Data {
        var contents = ESMFixture.tes4()
        contents += ESMFixture.topGroup("MISC", contents: miscRecords())
        contents += ESMFixture.topGroup("WEAP", contents: weaponRecord())
        contents += ESMFixture.topGroup("ARMO", contents: armorRecords())
        contents += ESMFixture.topGroup("EQUP", contents: equipSlotRecords())
        contents += ESMFixture.topGroup("LVLI", contents: leveledRecords())
        contents += ESMFixture.topGroup("OTFT", contents: outfitRecords())
        contents += ESMFixture.topGroup("NPC_", contents: actorRecords())
        contents += ESMFixture.topGroup("CONT", contents: containerRecords())
        return contents
    }

    // MARK: - Items

    private static func miscRecords() -> Data {
        item("MISC", formID: gold.rawValue, editorID: "Gold001", value: 1, weight: 0)
            + item("MISC", formID: lockpick.rawValue, editorID: "Lockpick", value: 5, weight: 0)
    }

    /// Two weapons whose ETYP links straddle the one-hand / two-hand split
    /// `EquipmentCatalog` reads through the EQUP graph, each with a MODL so
    /// the hand attachment has a path to load (issue #178). The DNAM animation
    /// types still match their families, so a suite that asserts against the
    /// animation graph reads the same weapons the same way.
    private static func weaponRecord() -> Data {
        weapon(WeaponSpec(
            formID: sword.rawValue, editorID: "IronSword", damage: 7,
            animation: 1, equipType: eitherHandSlot,
            model: "weapons\\iron\\sword.nif"
        ))
            + weapon(WeaponSpec(
                formID: greatsword.rawValue, editorID: "IronGreatsword", damage: 15,
                animation: 5, equipType: bothHandsSlot,
                model: "weapons\\iron\\greatsword.nif"
            ))
    }

    /// One weapon's authored numbers, bundled so the builder stays inside the
    /// parameter-count cap.
    private struct WeaponSpec {
        let formID: UInt32
        let editorID: String
        let damage: UInt16
        let animation: UInt8
        let equipType: FormID
        let model: String
    }

    private static func weapon(_ spec: WeaponSpec) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(spec.editorID))
        fields += ESMFixture.field("MODL", ESMFixture.zstring(spec.model))
        fields += ESMFixture.field(
            "DATA", InventoryFixture.weaponData(value: 25, weight: 9, damage: spec.damage)
        )
        fields += ESMFixture.field("DNAM", InventoryFixture.weaponDNAM(
            animation: spec.animation, speed: 1, reach: 1, flags: 0, skill: -1
        ))
        var equipTypeData = Data()
        equipTypeData.appendUInt32(spec.equipType.rawValue)
        fields += ESMFixture.field("ETYP", equipTypeData)
        return ESMFixture.record("WEAP", formID: spec.formID, data: fields)
    }

    /// The four EQUP records the two weapons resolve through, in the shape the
    /// vanilla master authors them: two leaves named by editor ID, and two
    /// composites that differ only in the DATA "use all parents" flag.
    private static func equipSlotRecords() -> Data {
        EquipSlotFixture.record(formID: rightHandSlot.rawValue, editorID: "RightHand")
            + EquipSlotFixture.record(formID: leftHandSlot.rawValue, editorID: "LeftHand")
            + EquipSlotFixture.record(
                formID: eitherHandSlot.rawValue,
                editorID: "EitherHand",
                parents: [leftHandSlot.rawValue, rightHandSlot.rawValue]
            )
            + EquipSlotFixture.record(
                formID: bothHandsSlot.rawValue,
                editorID: "BothHands",
                parents: [leftHandSlot.rawValue, rightHandSlot.rawValue],
                usesAllParents: true
            )
    }

    /// Body slots follow nif.xml bit numbering (bit N == biped slot 30 + N):
    /// body is slot 32, head slot 30, hands slot 33.
    private static func armorRecords() -> Data {
        armor(cuirass.rawValue, "IronCuirass", value: 125, weight: 30, slots: 1 << 2)
            + armor(helmet.rawValue, "IronHelmet", value: 60, weight: 5, slots: 1 << 0)
            + armor(leatherCuirass.rawValue, "LeatherCuirass", value: 40, weight: 8, slots: 1 << 2)
            + armor(gauntlets.rawValue, "IronGauntlets", value: 25, weight: 5, slots: 1 << 3)
    }

    private static func armor(
        _ formID: UInt32,
        _ editorID: String,
        value: Int32,
        weight: Float,
        slots: UInt32
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        var bod2 = Data()
        bod2.appendUInt32(slots)
        bod2.appendUInt32(2) // clothing
        fields += ESMFixture.field("BOD2", bod2)
        fields += ESMFixture.field(
            "DATA", InventoryFixture.valueWeightData(value: value, weight: weight)
        )
        return ESMFixture.record("ARMO", formID: formID, data: fields)
    }

    /// A record whose whole payload is EDID plus the 8-byte value+weight DATA,
    /// which is exactly the shape MISC and ARMO share.
    private static func item(
        _ type: String,
        formID: UInt32,
        editorID: String,
        value: Int32,
        weight: Float
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        fields += ESMFixture.field(
            "DATA", InventoryFixture.valueWeightData(value: value, weight: weight)
        )
        return ESMFixture.record(type, formID: formID, data: fields)
    }

    // MARK: - Leveled lists

    private static func leveledRecords() -> Data {
        var records = leveled(
            formID: singlePickList.rawValue,
            entries: [LeveledEntry(1, sword.rawValue), LeveledEntry(5, cuirass.rawValue)]
        )
        records += leveled(
            formID: bundleList.rawValue,
            flags: 0x04,
            entries: [LeveledEntry(1, cuirass.rawValue), LeveledEntry(1, helmet.rawValue, 2)]
        )
        records += leveled(
            formID: cyclicList.rawValue,
            entries: [LeveledEntry(1, cyclicList.rawValue)]
        )
        records += leveled(formID: emptyList.rawValue, entries: [])
        return records
    }

    /// One LVLO entry: level, target and per-entry count.
    struct LeveledEntry {
        let level: UInt16
        let reference: UInt32
        let count: UInt32

        init(_ level: UInt16, _ reference: UInt32, _ count: UInt32 = 1) {
            self.level = level
            self.reference = reference
            self.count = count
        }
    }

    private static func leveled(
        formID: UInt32,
        flags: UInt8 = 0,
        entries: [LeveledEntry]
    ) -> Data {
        var fields = ESMFixture.field("LVLF", Data([flags]))
        for entry in entries {
            var data = Data()
            data.appendUInt16(entry.level)
            data.appendUInt16(0)
            data.appendUInt32(entry.reference)
            data.appendUInt32(entry.count)
            fields += ESMFixture.field("LVLO", data)
        }
        return ESMFixture.record("LVLI", formID: formID, data: fields)
    }

    // MARK: - Outfits and actors

    private static func outfitRecords() -> Data {
        outfit(formID: guardOutfit.rawValue, items: [cuirass.rawValue, bundleList.rawValue])
            + outfit(formID: emptyOutfit.rawValue, items: [emptyList.rawValue])
    }

    private static func outfit(formID: UInt32, items: [UInt32]) -> Data {
        var inam = Data()
        for item in items {
            inam.appendUInt32(item)
        }
        return ESMFixture.record(
            "OTFT", formID: formID, data: ESMFixture.field("INAM", inam)
        )
    }

    private static func actorRecords() -> Data {
        var records = actor(formID: guardActor.rawValue, defaultOutfit: guardOutfit.rawValue)
        // Delegates its inventory upward: the ACBS `useInventory` flag plus a
        // TPLT means the parent's outfit wins over this record's own DOFT.
        records += actor(
            formID: templatedActor.rawValue,
            templateFlags: 0x0100,
            template: guardActor.rawValue,
            defaultOutfit: emptyOutfit.rawValue
        )
        records += actor(formID: outfitlessActor.rawValue, defaultOutfit: nil)
        return records
    }

    private static func actor(
        formID: UInt32,
        templateFlags: UInt16 = 0,
        template: UInt32? = nil,
        defaultOutfit: UInt32?
    ) -> Data {
        var acbs = Data()
        acbs.appendUInt32(0)
        for _ in 0 ..< 7 {
            acbs.appendUInt16(0)
        }
        acbs.appendUInt16(templateFlags)
        acbs.appendUInt16(0)
        acbs.appendUInt16(0)
        var fields = ESMFixture.field("ACBS", acbs)
        if let template {
            fields += InventoryFixture.formIDField("TPLT", template)
        }
        if let defaultOutfit {
            fields += InventoryFixture.formIDField("DOFT", defaultOutfit)
        }
        return ESMFixture.record("NPC_", formID: formID, data: fields)
    }

    // MARK: - Containers

    private static func containerRecords() -> Data {
        var records = container(
            formID: chest.rawValue,
            editorID: "Chest",
            entries: [
                (lockpick.rawValue, 3),
                (gold.rawValue, 1),
                (singlePickList.rawValue, 1)
            ]
        )
        records += container(
            formID: leveledChest.rawValue,
            editorID: "LeveledChest",
            entries: [(bundleList.rawValue, 2)]
        )
        records += container(formID: emptyChest.rawValue, editorID: "EmptyChest", entries: [])
        return records
    }

    private static func container(
        formID: UInt32,
        editorID: String,
        entries: [(item: UInt32, count: Int32)]
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        for entry in entries {
            fields += ESMFixture.field(
                "CNTO", InventoryFixture.cntoData(item: entry.item, count: entry.count)
            )
        }
        return ESMFixture.record("CONT", formID: formID, data: fields)
    }
}
