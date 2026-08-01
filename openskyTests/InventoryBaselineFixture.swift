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
//   0x00_0200  WEAP IronSword      (weight 9, value 25)
//   0x00_0300  ARMO IronCuirass    (weight 30, value 125)
//   0x00_0400  ARMO IronHelmet     (weight 5, value 60)
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
    static let cuirass = FormID(0x0000_0300)
    static let helmet = FormID(0x0000_0400)

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

    private static func weaponRecord() -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("IronSword"))
        fields += ESMFixture.field(
            "DATA", InventoryFixture.weaponData(value: 25, weight: 9, damage: 7)
        )
        return ESMFixture.record("WEAP", formID: sword.rawValue, data: fields)
    }

    private static func armorRecords() -> Data {
        item("ARMO", formID: cuirass.rawValue, editorID: "IronCuirass", value: 125, weight: 30)
            + item("ARMO", formID: helmet.rawValue, editorID: "IronHelmet", value: 60, weight: 5)
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
