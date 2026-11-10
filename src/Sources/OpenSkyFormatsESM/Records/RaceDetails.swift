// RACE fields beyond the appearance core: DATA, attacks, body and behavior
// models, movement, phonemes, and the per-sex head data with chargen morphs,
// presets and tint masks. Layout and sources: docs/formats/actors.md.

public import Foundation
public import OpenSkyFormatsCore

nonisolated struct RaceBodyPart: Equatable, Sendable {
    /// INDX: 0 upper body, 1 lower body, 2 hand, 3 foot, 4 tail.
    var index: UInt32
    var model: ModelData?
}

nonisolated public struct RaceHeadPart: Equatable, Sendable {
    /// INDX: 0 head, 1 eyes, 2 hair, 3 brows, 4 face.
    var index: UInt32
    /// HEAD, an HDPT.
    var part: FormID?
}

/// One MPAI and MPAV pair. The groups come in the order nose, brow, eye, lip.
nonisolated struct RaceMorphGroup: Equatable, Sendable {
    /// MPAI. xEdit leaves it unnamed.
    var index: Data?
    /// MPAV: the variant flags, then bytes xEdit leaves unnamed.
    var variants: Data?

    /// The first uint32 of MPAV: which variants the group offers.
    var flags: UInt32? {
        guard let variants, variants.count >= 4 else { return nil }
        var reader = BinaryReader(variants)
        return attempt { try reader.readUInt32() }
    }
}

nonisolated public struct RaceTintPreset: Equatable, Sendable {
    /// TINC, a CLFM.
    public var color: FormID?
    /// TINV.
    var defaultValue: Float?
    /// TIRS.
    var index: UInt16?

    /// `TINV` from 0 to 1. Some records store a percent, so a value over 1 is divided by 100.
    public var strength: Float {
        let value = defaultValue ?? 1
        return min(max(value > 1 ? value / 100 : value, 0), 1)
    }
}

nonisolated public struct RaceTintMask: Equatable, Sendable {
    /// TINI.
    public var index: UInt16?
    /// TINT, the mask texture.
    public var texturePath: String?
    /// TINP: 0 none, 1 lip, 2 cheek, 3 eyeliner, 6 skin tone, 7 paint, 14 dirt. See the page.
    public var maskType: UInt16?
    /// TIND, a CLFM.
    var presetDefault: FormID?
    public var presets: [RaceTintPreset] = []

    /// The preset `TIND` names, else the first. A face without this mask's layer
    /// takes it, as the Creation Kit bakes such faces.
    public var defaultPreset: RaceTintPreset? {
        presets.first { $0.color != nil && $0.color == presetDefault } ?? presets.first
    }
}

nonisolated public struct RaceHeadData: Equatable, Sendable {
    public var headParts: [RaceHeadPart] = []
    var morphs: [RaceMorphGroup] = []
    /// RPRM or RPRF, preset NPC_ records.
    public var presets: [FormID] = []
    /// AHCM or AHCF, CLFM records.
    public var hairColors: [FormID] = []
    /// FTSM or FTSF, TXST records.
    public var faceDetailTextures: [FormID] = []
    /// DFTM or DFTF, a TXST.
    public var defaultFaceTexture: FormID?
    public var tintMasks: [RaceTintMask] = []
    var model: ModelData?
}

nonisolated public struct RaceDetails: Equatable, Sendable {
    public var description: LString?
    public var keywords: [FormID] = []
    public var properties: RaceProperties?
    /// ANAM with its MODT, per sex.
    var skeletons = GenderPair<ModelData?>(male: nil, female: nil)
    /// MTNM, four-letter movement type names.
    var movementTypeNames: [String] = []
    /// VTCK, VTYP records.
    var voices: GenderPair<FormID?>?
    /// DNAM, ARMO records.
    public var decapitateArmors: GenderPair<FormID?>?
    /// HCLF, CLFM records.
    var defaultHairColors: GenderPair<FormID?>?
    /// TINL. Stale on most races, so nothing checks it against the masks.
    var tintCount: UInt16?
    /// PNAM and UNAM, the FaceGen main and face clamps.
    var faceGenMainClamp: Float?
    var faceGenFaceClamp: Float?
    /// ATKR, a RACE whose attacks this race uses.
    var attackRace: FormID?
    var attacks: [RaceAttack] = []
    var bodyParts = GenderPair<[RaceBodyPart]>(male: [], female: [])
    /// HNAM, HDPT records.
    var hairs: [FormID] = []
    /// ENAM, EYES records.
    var eyes: [FormID] = []
    /// GNAM, a BPTD.
    public var bodyPartData: FormID?
    public var behaviorGraphs = GenderPair<ModelData?>(male: nil, female: nil)
    /// NAM4 MATT, NAM5 IPDS, NAM7 ARTO, ONAM and LNAM SNDR.
    public var materialType: FormID?
    var impactDataSet: FormID?
    public var decapitationEffect: FormID?
    var openLootSound: FormID?
    var closeLootSound: FormID?
    /// NAME, the 32 biped object names.
    var bipedObjectNames: [String] = []
    var movementTypes: [RaceMovementType] = []
    /// VNAM: bit n allows equipment type n (0 hand-to-hand to 12 crossbow).
    var equipmentFlags: UInt32?
    /// QNAM, EQUP records.
    var equipSlots: [FormID] = []
    /// UNES, an EQUP.
    var unarmedEquipSlot: FormID?
    /// PHTN.
    var phonemeTargetNames: [String] = []
    /// PHWT, one entry per phoneme, 8 or 16 floats each.
    var phonemeWeights: [[Float]] = []
    /// WKMV, RNMV, SWMV, FLMV, SNMV, SPMV: MOVT records.
    var baseMovement: [FourCC: FormID] = [:]
    public var headData = GenderPair(male: RaceHeadData(), female: RaceHeadData())
    /// NAM8, a RACE.
    public var morphRace: FormID?
    /// RNAM, a RACE.
    var armorRace: FormID?
}
