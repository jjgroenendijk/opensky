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
    outfitItems: [UInt32] = [0x300]
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
        try? armor(formID: 0x320, race: 0x19, slots: 0b0100, armatures: [0x321])
    ]
    let addons = [
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
            models: ("clothes_m.nif", "clothes_f.nif")
        ),
        try? arma(
            formID: 0x321, race: 0x19, additional: [0x100], slots: 0b0100,
            models: ("robes_m.nif", "robes_f.nif")
        )
    ]
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
        formIDResolver: FormIDResolver(pluginName: "Follower.esp", masters: ["Skyrim.esm"])
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
    models: (male: String?, female: String?)
) throws -> ArmorAddon {
    var fields = bod2Field(slots: slots) + formIDField("RNAM", race)
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

extension Race: FormIdentified {}
extension Armor: FormIdentified {}
extension ArmorAddon: FormIdentified {}
extension Outfit: FormIdentified {}
extension LeveledList: FormIdentified {}

extension Array {
    /// Raw-FormID-keyed index (resolver convention), dropping build failures.
    fileprivate func keyed<Value: FormIdentified>() -> [UInt32: Value] where Element == Value? {
        Dictionary(uniqueKeysWithValues: compactMap(\.self).map { ($0.formID.rawValue, $0) })
    }
}
