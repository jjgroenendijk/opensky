// One synthetic plugin with every inventory baseline source. Tests go through
// `InventoryBaselineResolver.build(from:)`, the engine's own indexing path.
// The FormID constants below are what suites assert against.

@testable import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

public enum InventoryBaselineFixture {
    public static let gold = FormID(0x0000_000F)
    public static let lockpick = FormID(0x0000_0100)
    public static let sword = FormID(0x0000_0200)
    public static let greatsword = FormID(0x0000_0210)
    public static let cuirass = FormID(0x0000_0300)
    public static let helmet = FormID(0x0000_0400)
    public static let leatherCuirass = FormID(0x0000_0410)
    public static let gauntlets = FormID(0x0000_0420)

    public static let rightHandSlot = FormID(0x0000_0500)
    public static let leftHandSlot = FormID(0x0000_0510)
    public static let eitherHandSlot = FormID(0x0000_0520)
    public static let bothHandsSlot = FormID(0x0000_0530)

    public static let singlePickList = FormID(0x0000_1000)
    public static let bundleList = FormID(0x0000_1010)
    public static let cyclicList = FormID(0x0000_1020)
    public static let emptyList = FormID(0x0000_1030)

    public static let guardOutfit = FormID(0x0000_2000)
    public static let emptyOutfit = FormID(0x0000_2010)

    public static let guardActor = FormID(0x0000_3000)
    public static let templatedActor = FormID(0x0000_3010)
    public static let outfitlessActor = FormID(0x0000_3020)

    public static let chest = FormID(0x0000_4000)
    public static let leveledChest = FormID(0x0000_4010)
    public static let emptyChest = FormID(0x0000_4020)

    public static func resolver() throws -> InventoryBaselineResolver {
        try InventoryBaselineResolver.build(from: ESMFile(data: pluginBytes()))
    }

    // MARK: - Items

    private static func miscRecords() -> Data {
        item("MISC", formID: gold.rawValue, editorID: "Gold001", value: 1, weight: 0)
            + item("MISC", formID: lockpick.rawValue, editorID: "Lockpick", value: 5, weight: 0)
    }

    /// Two weapons on either side of the one-hand / two-hand EQUP split, each
    /// with a MODL so the hand attachment can load. DNAM animation types match
    /// their families.
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
    public struct LeveledEntry {
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

extension InventoryBaselineFixture {
    /// - Parameter playerOutfit: gives the `Player` record that outfit.
    public static func pluginBytes(playerOutfit: FormID? = nil) -> Data {
        var contents = ESMFixture.tes4()
        contents += ESMFixture.topGroup("MISC", contents: miscRecords())
        contents += ESMFixture.topGroup("WEAP", contents: weaponRecord())
        contents += ESMFixture.topGroup("ARMO", contents: armorRecords())
        contents += ESMFixture.topGroup("EQUP", contents: equipSlotRecords())
        contents += ESMFixture.topGroup("LVLI", contents: leveledRecords())
        contents += ESMFixture.topGroup("OTFT", contents: outfitRecords())
        contents += ESMFixture.topGroup(
            "NPC_",
            contents: actorRecords() + playerRecord(playerOutfit)
        )
        contents += ESMFixture.topGroup("CONT", contents: containerRecords())
        return contents
    }

    /// The `Player` NPC_ record, or nothing when it wears no outfit.
    private static func playerRecord(_ outfit: FormID?) -> Data {
        guard let outfit else { return Data() }
        return actor(
            formID: InventoryBaselineResolver.playerBase.rawValue,
            defaultOutfit: outfit.rawValue
        )
    }
}
