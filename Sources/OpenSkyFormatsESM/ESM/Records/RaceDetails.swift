// RACE fields beyond the appearance core: DATA, attacks, body and behavior
// models, movement, phonemes, and the per-sex head data with chargen morphs,
// presets and tint masks. Layout and sources: docs/formats/actors.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct RaceBodyPart: Equatable, Sendable {
    /// INDX: 0 upper body, 1 lower body, 2 hand, 3 foot, 4 tail.
    public var index: UInt32
    public var model: ModelData?
}

nonisolated public struct RaceHeadPart: Equatable, Sendable {
    /// INDX: 0 head, 1 eyes, 2 hair, 3 brows, 4 face.
    public var index: UInt32
    /// HEAD, an HDPT.
    public var part: FormID?
}

/// One MPAI and MPAV pair. The groups come in the order nose, brow, eye, lip.
nonisolated public struct RaceMorphGroup: Equatable, Sendable {
    /// MPAI. xEdit leaves it unnamed.
    public var index: Data?
    /// MPAV: the variant flags, then bytes xEdit leaves unnamed.
    public var variants: Data?

    /// The first uint32 of MPAV: which variants the group offers.
    public var flags: UInt32? {
        guard let variants, variants.count >= 4 else { return nil }
        var reader = BinaryReader(variants)
        return try? reader.readUInt32()
    }
}

nonisolated public struct RaceTintPreset: Equatable, Sendable {
    /// TINC, a CLFM.
    public var color: FormID?
    /// TINV.
    public var defaultValue: Float?
    /// TIRS.
    public var index: UInt16?
}

nonisolated public struct RaceTintMask: Equatable, Sendable {
    /// TINI.
    public var index: UInt16?
    /// TINT, the mask texture.
    public var texturePath: String?
    /// TINP: 0 none, 1 lip, 2 cheek, 3 eyeliner, 6 skin tone, 7 paint, 14 dirt. See the page.
    public var maskType: UInt16?
    /// TIND, a CLFM.
    public var presetDefault: FormID?
    public var presets: [RaceTintPreset] = []
}

nonisolated public struct RaceHeadData: Equatable, Sendable {
    public var headParts: [RaceHeadPart] = []
    public var morphs: [RaceMorphGroup] = []
    /// RPRM or RPRF, preset NPC_ records.
    public var presets: [FormID] = []
    /// AHCM or AHCF, CLFM records.
    public var hairColors: [FormID] = []
    /// FTSM or FTSF, TXST records.
    public var faceDetailTextures: [FormID] = []
    /// DFTM or DFTF, a TXST.
    public var defaultFaceTexture: FormID?
    public var tintMasks: [RaceTintMask] = []
    public var model: ModelData?
}

nonisolated public struct RaceDetails: Equatable, Sendable {
    public var description: LString?
    public var keywords: [FormID] = []
    public var properties: RaceProperties?
    /// ANAM with its MODT, per sex.
    public var skeletons = GenderPair<ModelData?>(male: nil, female: nil)
    /// MTNM, four-letter movement type names.
    public var movementTypeNames: [String] = []
    /// VTCK, VTYP records.
    public var voices: GenderPair<FormID?>?
    /// DNAM, ARMO records.
    public var decapitateArmors: GenderPair<FormID?>?
    /// HCLF, CLFM records.
    public var defaultHairColors: GenderPair<FormID?>?
    /// TINL. Stale on most races, so nothing checks it against the masks.
    public var tintCount: UInt16?
    /// PNAM and UNAM, the FaceGen main and face clamps.
    public var faceGenMainClamp: Float?
    public var faceGenFaceClamp: Float?
    /// ATKR, a RACE whose attacks this race uses.
    public var attackRace: FormID?
    public var attacks: [RaceAttack] = []
    public var bodyParts = GenderPair<[RaceBodyPart]>(male: [], female: [])
    /// HNAM, HDPT records.
    public var hairs: [FormID] = []
    /// ENAM, EYES records.
    public var eyes: [FormID] = []
    /// GNAM, a BPTD.
    public var bodyPartData: FormID?
    public var behaviorGraphs = GenderPair<ModelData?>(male: nil, female: nil)
    /// NAM4 MATT, NAM5 IPDS, NAM7 ARTO, ONAM and LNAM SNDR.
    public var materialType: FormID?
    public var impactDataSet: FormID?
    public var decapitationEffect: FormID?
    public var openLootSound: FormID?
    public var closeLootSound: FormID?
    /// NAME, the 32 biped object names.
    public var bipedObjectNames: [String] = []
    public var movementTypes: [RaceMovementType] = []
    /// VNAM: bit n allows equipment type n (0 hand-to-hand to 12 crossbow).
    public var equipmentFlags: UInt32?
    /// QNAM, EQUP records.
    public var equipSlots: [FormID] = []
    /// UNES, an EQUP.
    public var unarmedEquipSlot: FormID?
    /// PHTN.
    public var phonemeTargetNames: [String] = []
    /// PHWT, one entry per phoneme, 8 or 16 floats each.
    public var phonemeWeights: [[Float]] = []
    /// WKMV, RNMV, SWMV, FLMV, SNMV, SPMV: MOVT records.
    public var baseMovement: [FourCC: FormID] = [:]
    public var headData = GenderPair(male: RaceHeadData(), female: RaceHeadData())
    /// NAM8, a RACE.
    public var morphRace: FormID?
    /// RNAM, a RACE.
    public var armorRace: FormID?
}
