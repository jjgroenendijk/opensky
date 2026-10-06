// ARMA record: how an ARMO piece shows on a body, per gender, plus the races
// it applies to. MOD4/MOD5 first-person models are optional, so a missing one
// means "not on the arms". A higher DNAM priority draws over a lower one; no
// DNAM reads as 0. Layout and sources: docs/formats/armor.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct ArmorAddon: Sendable {
    public let formID: FormID
    public let editorID: String?
    /// BOD2/BODT biped slots + armor type; nil when absent.
    public let bodyTemplate: BodyTemplate?
    /// RNAM — the one primary race the armature must have.
    public let primaryRace: FormID?
    /// MODL — extra races this armature also applies to.
    public let additionalRaces: [FormID]
    /// MOD2 with its MO2T/MO2S — male biped model.
    public let maleModel: ModelData?
    /// MOD3 group — female biped model.
    public let femaleModel: ModelData?
    /// MOD4 group — male first-person model; nil when the armature shows
    /// nothing on the player's own arms.
    public let maleFirstPersonModel: ModelData?
    /// MOD5 group — female first-person model.
    public let femaleFirstPersonModel: ModelData?
    /// NAM0/NAM1 — the TXST that skins exposed skin, per gender.
    public let maleSkinTexture: FormID?
    public let femaleSkinTexture: FormID?
    /// NAM2/NAM3 — FLST of TXSTs the skin texture may swap to, per gender.
    public let maleSkinTextureSwapList: FormID?
    public let femaleSkinTextureSwapList: FormID?
    /// ONAM — an ARTO shown with the armature.
    public let artObject: FormID?
    /// DNAM male draw priority; 0 when the record carries no DNAM.
    public let malePriority: UInt8
    /// DNAM female draw priority; 0 when the record carries no DNAM.
    public let femalePriority: UInt8
    /// DNAM weapon adjust — how far a weapon floats from its attachment point
    /// on an actor wearing this armature. Decoded now because the field is
    /// read here anyway; the hand attachment does not apply it yet.
    public let weaponAdjust: Float
    /// SNDD: the FSTS footstep set an actor wearing this armature walks with
    /// (xEdit `wbFormIDCk(SNDD, 'Footstep Sound', [FSTS, NULL])`). Only boot and
    /// bare-feet armatures carry one. Nil when absent or null.
    public let footstepSound: FormID?
    public let skipped: FieldTally

    /// The draw priority that applies to one gender.
    public func priority(female: Bool) -> UInt8 {
        female ? femalePriority : malePriority
    }

    /// The first-person model for one gender, with the same cross-gender
    /// fallback the third-person selection uses: an armature that declares only
    /// MOD4 shows it on both genders rather than showing nothing.
    public func firstPersonModelPath(female: Bool) -> String? {
        let preferred = female ? femaleFirstPersonModelPath : maleFirstPersonModelPath
        return preferred ?? maleFirstPersonModelPath ?? femaleFirstPersonModelPath
    }

    public var maleModelPath: String? {
        maleModel?.path
    }

    public var femaleModelPath: String? {
        femaleModel?.path
    }

    public var maleFirstPersonModelPath: String? {
        maleFirstPersonModel?.path
    }

    public var femaleFirstPersonModelPath: String? {
        femaleFirstPersonModel?.path
    }

    public init(record: ESMRecord) throws {
        var rest = try RecordFields(record: record, type: "ARMA")
        formID = rest.formID
        editorID = rest.editorID()
        bodyTemplate = rest.field("BOD2", BodyTemplate.init(bod2:))
            ?? rest.field("BODT", BodyTemplate.init(bodt:))
        primaryRace = rest.read("RNAM") { try $0.readFormID() }
        additionalRaces = rest.readAll("MODL") { try $0.readFormID() }
        let priorities = rest.field("DNAM", DrawPriorities.init(field:)) ?? DrawPriorities()
        malePriority = priorities.male
        femalePriority = priorities.female
        weaponAdjust = priorities.weaponAdjust
        footstepSound = rest.formID("SNDD")
        maleModel = rest.model(path: "MOD2", hashes: "MO2T", alternates: "MO2S")
        femaleModel = rest.model(path: "MOD3", hashes: "MO3T", alternates: "MO3S")
        maleFirstPersonModel = rest.model(path: "MOD4", hashes: "MO4T", alternates: "MO4S")
        femaleFirstPersonModel = rest.model(path: "MOD5", hashes: "MO5T", alternates: "MO5S")
        maleSkinTexture = rest.formID("NAM0")
        femaleSkinTexture = rest.formID("NAM1")
        maleSkinTextureSwapList = rest.formID("NAM2")
        femaleSkinTextureSwapList = rest.formID("NAM3")
        artObject = rest.formID("ONAM")
        skipped = rest.finish()
    }

    /// The three DNAM members the engine keeps, with the all-zero reading a
    /// DNAM-less ARMA gets. A payload shorter than the documented 12 bytes
    /// decodes as far as it reaches rather than throwing: a missing priority
    /// degrades to the naked-body level, which is the same answer as no DNAM,
    /// while refusing the record would drop an armature that renders fine.
    private struct DrawPriorities {
        var male: UInt8 = 0
        var female: UInt8 = 0
        var weaponAdjust: Float = 0

        init() {}

        init(field: ESMField) throws {
            guard field.data.count >= 2 else { return }
            var reader = BinaryReader(field.data)
            male = try reader.readUInt8()
            female = try reader.readUInt8()
            guard field.data.count >= 12 else { return }
            reader.skip(6) // weight sliders + detection sound + one unused byte
            weaponAdjust = try reader.readFloat32()
        }
    }
}
