// Shared synthetic scenario for ActorVisualResolver tests — records built
// in code via ESMFixture, never extracted game files (AGENTS.md "Legal & IP
// boundary"). Used by ActorVisualResolutionTests.

import Foundation
@testable import opensky

/// Standard scenario: one race (skin torso+feet), an alternate skin, clothes
/// covering the body slot reachable directly (outfit) or through an LVLI
/// (leveledOutfit), plus broken lists for failure tests. Parameters carve
/// out the variants individual tests need.
func makeResolver(
    raceSkin: UInt32? = 0x200,
    raceFaceGenHead: Bool = true,
    femaleSkeleton: String? = "skel_f.nif",
    feetMaleModel: String? = "feet_m.nif",
    feetFemaleModel: String? = "feet_f.nif",
    altSkinArmatures: [UInt32] = [0x210],
    outfitItems: [UInt32] = [0x300],
    clothesPriority: UInt8 = 0,
    robesPriority: UInt8 = 0
) -> ActorVisualResolver {
    let races = [
        try? race(
            formID: 0x100, skin: raceSkin, faceGenHead: raceFaceGenHead,
            maleSkeleton: "skel_m.nif", femaleSkeleton: femaleSkeleton
        )
    ]
    let armors = [
        try? armor(formID: 0x200, race: 0x19, slots: 0, armatures: [0x210, 0x211, 0x212]),
        try? armor(formID: 0x201, race: 0x19, slots: 0, armatures: altSkinArmatures),
        try? armor(formID: 0x300, race: 0x19, slots: 0b0100, armatures: [0x310]),
        try? armor(formID: 0x320, race: 0x19, slots: 0b0100, armatures: [0x321]),
        try? armor(formID: 0x330, race: 0x19, slots: 0b10000, armatures: [0x331]),
        // Hooded robes: one ARMO whose two armatures are listed in the
        // opposite order to their DNAM draw priority, the shape vanilla
        // ClothesMonkRobesHooded has (issue #384).
        try? armor(formID: 0x340, race: 0x19, slots: 0b0100, armatures: [0x342, 0x341])
    ]
    let addons = makeArmorAddons(
        feetMaleModel: feetMaleModel,
        feetFemaleModel: feetFemaleModel,
        clothesPriority: clothesPriority,
        robesPriority: robesPriority
    )
    let outfits = [
        try? outfit(formID: 0x400, items: outfitItems),
        try? outfit(formID: 0x410, items: [0x500]),
        try? outfit(formID: 0x420, items: [0x530])
    ]
    let lists = [
        try? lvli(formID: 0x500, entries: [(1, 0x300), (5, 0x320)]),
        try? lvli(formID: 0x510, entries: [(1, 0x510)]),
        try? lvli(formID: 0x520, entries: []),
        try? lvli(formID: 0x530, flags: 0x04, entries: [(1, 0x300), (1, 0x320)])
    ]
    return ActorVisualResolver(
        races: races.keyed(),
        armors: armors.keyed(),
        armorAddons: addons.keyed(),
        outfits: outfits.keyed(),
        leveledItems: lists.keyed(),
        formIDResolver: FormIDResolver(pluginName: "Follower.esp", masters: ["Skyrim.esm"]),
        equipment: makeEquipmentCatalog()
    )
}

/// The armatures the ARMOs above point at: skin torso/feet plus one foreign-race
/// armature that never resolves, the clothes and robes pieces the priority tests
/// vary, gloves, and the hood + robes pair that shares one ARMO.
private func makeArmorAddons(
    feetMaleModel: String?,
    feetFemaleModel: String?,
    clothesPriority: UInt8,
    robesPriority: UInt8
) -> [ArmorAddon?] {
    [
        try? arma(
            formID: 0x210, race: 0x19, additional: [0x100], slots: 0b0100,
            models: ("torso_m.nif", "torso_f.nif")
        ),
        try? arma(
            formID: 0x211, race: 0x100, additional: [], slots: 0b1000_0000,
            models: (feetMaleModel, feetFemaleModel)
        ),
        try? arma(
            formID: 0x212, race: 0x999, additional: [], slots: 0b0100,
            models: ("foreign_m.nif", "foreign_f.nif")
        ),
        try? arma(
            formID: 0x310, race: 0x19, additional: [0x100], slots: 0b0100,
            models: ("clothes_m.nif", "clothes_f.nif"), priority: clothesPriority
        ),
        try? arma(
            formID: 0x321, race: 0x19, additional: [0x100], slots: 0b0100,
            models: ("robes_m.nif", "robes_f.nif"), priority: robesPriority
        ),
        try? arma(
            formID: 0x331, race: 0x19, additional: [0x100], slots: 0b10000,
            models: ("gloves_m.nif", "gloves_f.nif")
        ),
        // Vanilla MonkHoodAA and MonkRobesAA priorities (issue #384).
        try? arma(
            formID: 0x341, race: 0x19, additional: [0x100], slots: 0b0010,
            models: ("hood_m.nif", "hood_f.nif"), priority: 10
        ),
        try? arma(
            formID: 0x342, race: 0x19, additional: [0x100], slots: 0b0100,
            models: ("hoodedrobes_m.nif", "hoodedrobes_f.nif"), priority: 15
        )
    ]
}

/// Slot data matching the ARMO/ARMA fixtures above, plus two weapons: a
/// one-handed sword (right hand) and a two-handed greatsword (both hands).
///
/// Built by hand rather than through `EquipmentCatalog.build(from:)`, because
/// these fixtures are decoded records rather than an `ESMFile` — the builder is
/// covered separately against synthetic plugin bytes.
func makeEquipmentCatalog(
    swordModel: String? = "sword.nif",
    extra: [UInt32: EquippableItem] = [:]
) -> EquipmentCatalog {
    var items: [UInt32: EquippableItem] = [
        // Torso clothes and robes both claim slot 32, so equipping one
        // displaces the other. Gloves claim slot 34 and coexist with both.
        0x300: equippable(0x300, slots: 0b0100),
        0x320: equippable(0x320, slots: 0b0100),
        0x330: equippable(0x330, slots: 0b10000),
        0x600: EquippableItem(
            formID: FormID(0x600),
            occupancy: EquipmentOccupancy(hands: .rightHand),
            modelPath: swordModel
        ),
        0x610: EquippableItem(
            formID: FormID(0x610),
            occupancy: EquipmentOccupancy(hands: .bothHands),
            modelPath: "greatsword.nif"
        ),
        // A potion: carryable, occupies nothing, never equippable.
        0x700: EquippableItem(
            formID: FormID(0x700), occupancy: .none, modelPath: nil
        )
    ]
    items.merge(extra) { _, new in new }
    return EquipmentCatalog(items: items)
}

private func equippable(_ raw: UInt32, slots: UInt32) -> EquippableItem {
    EquippableItem(
        formID: FormID(raw),
        occupancy: EquipmentOccupancy(slots: BodySlots(rawValue: slots)),
        modelPath: nil
    )
}

/// Template-resolved appearance with every field sourced from the base NPC_.
func appearance(
    female: Bool = false,
    race: UInt32? = 0x100,
    wornArmor: UInt32? = nil,
    headParts: [UInt32] = [0x2000],
    headSource: UInt32 = 0x1000,
    outfit: UInt32? = nil
) -> ResolvedActorAppearance {
    let base = FormID(0x1000)
    return ResolvedActorAppearance(
        base: base,
        chain: [.npc(base)],
        isFemale: ActorSourcedField(value: female, source: base),
        race: ActorSourcedField(value: race.map(FormID.init), source: base),
        wornArmor: ActorSourcedField(value: wornArmor.map(FormID.init), source: base),
        headParts: ActorSourcedField(
            value: headParts.map(FormID.init), source: FormID(headSource)
        ),
        defaultOutfit: ActorSourcedField(value: outfit.map(FormID.init), source: base)
    )
}

// MARK: - Record builders (synthetic bytes -> decoded values)

private func parseRecord(_ bytes: Data) throws -> ESMRecord {
    let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
    guard case let .record(record)? = children.first else {
        throw ESMError.malformed("fixture did not produce a record")
    }
    return record
}

private func formIDField(_ type: String, _ value: UInt32) -> Data {
    var data = Data()
    data.appendUInt32(value)
    return ESMFixture.field(type, data)
}

/// ARMA DNAM, 12 bytes: male priority, female priority, four bytes of weight
/// slider flags, detection sound, one unused byte, then the weapon-adjust
/// float (UESP + xEdit; see ArmorAddon.swift).
func dnamField(male: UInt8, female: UInt8, weaponAdjust: Float = 0) -> Data {
    var data = Data([male, female, 0, 0, 0, 0, 0, 0])
    data.appendFloat32(weaponAdjust)
    return ESMFixture.field("DNAM", data)
}

private func bod2Field(slots: UInt32) -> Data {
    var data = Data()
    data.appendUInt32(slots)
    data.appendUInt32(2)
    return ESMFixture.field("BOD2", data)
}

private func race(
    formID: UInt32,
    skin: UInt32?,
    faceGenHead: Bool = true,
    maleSkeleton: String,
    femaleSkeleton: String?
) throws -> Race {
    var fields = Data()
    if let skin {
        fields += formIDField("WNAM", skin)
    }
    // DATA: 0x20 bytes of stats, then the uint32 flags word (UESP RACE).
    var raceData = Data(count: 0x20)
    raceData.appendUInt32(faceGenHead ? 0x3 : 0x100)
    fields += ESMFixture.field("DATA", raceData)
    fields += ESMFixture.field("MNAM", Data())
    fields += ESMFixture.field("ANAM", ESMFixture.zstring(maleSkeleton))
    if let femaleSkeleton {
        fields += ESMFixture.field("FNAM", Data())
        fields += ESMFixture.field("ANAM", ESMFixture.zstring(femaleSkeleton))
    }
    return try Race(
        record: parseRecord(ESMFixture.record("RACE", formID: formID, data: fields)),
        localized: false
    )
}

private func armor(
    formID: UInt32,
    race: UInt32,
    slots: UInt32,
    armatures: [UInt32]
) throws -> Armor {
    var fields = formIDField("RNAM", race) + bod2Field(slots: slots)
    for armature in armatures {
        fields += formIDField("MODL", armature)
    }
    return try Armor(
        record: parseRecord(ESMFixture.record("ARMO", formID: formID, data: fields)),
        localized: false
    )
}

private func arma(
    formID: UInt32,
    race: UInt32,
    additional: [UInt32],
    slots: UInt32,
    models: (male: String?, female: String?),
    priority: UInt8 = 0
) throws -> ArmorAddon {
    var fields = bod2Field(slots: slots) + formIDField("RNAM", race)
    if priority > 0 {
        fields += dnamField(male: priority, female: priority)
    }
    if let male = models.male {
        fields += ESMFixture.field("MOD2", ESMFixture.zstring(male))
    }
    if let female = models.female {
        fields += ESMFixture.field("MOD3", ESMFixture.zstring(female))
    }
    for extra in additional {
        fields += formIDField("MODL", extra)
    }
    return try ArmorAddon(
        record: parseRecord(ESMFixture.record("ARMA", formID: formID, data: fields))
    )
}

private func outfit(formID: UInt32, items: [UInt32]) throws -> Outfit {
    var inam = Data()
    for item in items {
        inam.appendUInt32(item)
    }
    return try Outfit(
        record: parseRecord(ESMFixture.record(
            "OTFT", formID: formID, data: ESMFixture.field("INAM", inam)
        ))
    )
}

private func lvli(
    formID: UInt32,
    flags: UInt8 = 0,
    entries: [(level: UInt16, reference: UInt32)]
) throws -> LeveledList {
    var fields = ESMFixture.field("LVLF", Data([flags]))
    for entry in entries {
        var data = Data()
        data.appendUInt16(entry.level)
        data.appendUInt16(0)
        data.appendUInt32(entry.reference)
        data.appendUInt32(1)
        fields += ESMFixture.field("LVLO", data)
    }
    return try LeveledList(
        record: parseRecord(ESMFixture.record("LVLI", formID: formID, data: fields))
    )
}

private protocol FormIdentified {
    var formID: FormID { get }
}

nonisolated extension Race: FormIdentified {}
nonisolated extension Armor: FormIdentified {}
nonisolated extension ArmorAddon: FormIdentified {}
nonisolated extension Outfit: FormIdentified {}
nonisolated extension LeveledList: FormIdentified {}

extension Array {
    /// Raw-FormID-keyed index (resolver convention), dropping build failures.
    fileprivate func keyed<Value: FormIdentified>() -> [UInt32: Value] where Element == Value? {
        Dictionary(uniqueKeysWithValues: compactMap(\.self).map { ($0.formID.rawValue, $0) })
    }
}

/// One ACHR placement, shared by the assembly suites.
func placedActor(
    position: SIMD3<Float> = .zero,
    rotation: SIMD3<Float> = .zero,
    scale: Float = 1
) throws -> PlacedActor {
    var name = Data()
    name.appendUInt32(0x1000)
    var placement = Data()
    for value in [
        position.x, position.y, position.z,
        rotation.x, rotation.y, rotation.z
    ] {
        placement.appendFloat32(value)
    }
    var xscl = Data()
    xscl.appendFloat32(scale)
    let bytes = ESMFixture.record(
        "ACHR",
        formID: 0x9000,
        data: ESMFixture.field("NAME", name)
            + ESMFixture.field("DATA", placement)
            + ESMFixture.field("XSCL", xscl)
    )
    let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
    guard case let .record(record)? = children.first else {
        throw ESMError.malformed("actor fixture did not produce a record")
    }
    return try PlacedActor(record: record)
}
