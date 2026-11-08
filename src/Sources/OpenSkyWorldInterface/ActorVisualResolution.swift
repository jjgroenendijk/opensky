import Foundation
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData

/// Everything milestone 5.2 resolves for one placed actor.
nonisolated public struct ResolvedActorVisual: Equatable, Sendable {
    public let appearance: ResolvedActorAppearance
    /// RACE ANAM for the resolved gender; nil -> reason-tagged skip.
    public let skeletonPath: String?
    /// The ARMO providing naked skin (after WNAM fallback).
    public let skin: FormID
    /// Union of equipped outfit ARMO body slots — the skin mask.
    public let equippedSlots: BodySlots
    public let parts: [ResolvedBodyPart]
    /// Rigid bone attachments: weapons and a worn shield.
    public let attachments: [ResolvedAttachment]
    /// True when a runtime equipped set replaced the plugin `defaultOutfit`.
    public let usesRuntimeEquipment: Bool
    /// Nil when the race does not use baked FaceGen heads (RACE DATA flag
    /// 0x2 clear — creature races like cow/dog/bear have no facegeom files).
    public let faceGenMeshPath: String?
    public let faceGenTintPath: String?
    public let skips: [AppearanceSkip]
    /// The parts an assembled head would show. Empty for a race without FaceGen.
    public var headParts = HeadPartSet(parts: [], misses: [])
    public var headSource = ActorHeadSource.baked
    /// Laid over the baked FaceGen head, such as a script's eye texture.
    public var faceGenSurface: ModelSurfaceOverride?
    /// The side of a decapitation the face and head parts draw; nil draws all of them.
    public var headCut: DismemberCut?

    public init(
        appearance: ResolvedActorAppearance,
        skeletonPath: String?,
        skin: FormID,
        equippedSlots: BodySlots,
        parts: [ResolvedBodyPart],
        attachments: [ResolvedAttachment],
        usesRuntimeEquipment: Bool,
        faceGenMeshPath: String?,
        faceGenTintPath: String?,
        skips: [AppearanceSkip],
        headParts: HeadPartSet = HeadPartSet(parts: [], misses: []),
        headSource: ActorHeadSource = ActorHeadSource.baked,
        faceGenSurface: ModelSurfaceOverride? = nil,
        headCut: DismemberCut? = nil
    ) {
        self.appearance = appearance
        self.skeletonPath = skeletonPath
        self.skin = skin
        self.equippedSlots = equippedSlots
        self.parts = parts
        self.attachments = attachments
        self.usesRuntimeEquipment = usesRuntimeEquipment
        self.faceGenMeshPath = faceGenMeshPath
        self.faceGenTintPath = faceGenTintPath
        self.skips = skips
        self.headParts = headParts
        self.headSource = headSource
        self.faceGenSurface = faceGenSurface
        self.headCut = headCut
    }
}

/// Reason-tagged degrade: the part is absent from `parts` on purpose, and
/// the reason says why (exact accounting, no silent drops).
nonisolated public struct AppearanceSkip: Equatable, Sendable {
    nonisolated public enum Reason: Equatable, Sendable {
        /// RACE has no skeleton ANAM for the resolved gender.
        case noSkeletonForGender
        /// ARMO armature FormID matches no ARMA record.
        case danglingArmature
        /// ARMO has no armature compatible with the actor's race.
        case noCompatibleArmature
        /// Compatible ARMA has neither a MOD2 nor a MOD3 model.
        case noModel
        /// Skin armature's slots are covered by equipped outfit slots.
        case maskedByOutfit
        /// Armature already provided by an earlier piece.
        case duplicateArmature
        /// ARMO carries no BOD2/BODT — contributes nothing to the mask.
        case missingBodySlots
        /// A runtime-equipped item is neither a known ARMO nor a weapon with a
        /// model, so it contributes no geometry.
        case unrenderableEquipment
        /// The armature declares no MOD4/MOD5, so it adds nothing to the first-person
        /// rig. Only the first-person projection produces this.
        case noFirstPersonModel
    }

    /// The record the skip is about (ARMA, ARMO, or RACE FormID).
    public let subject: FormID
    public let reason: Reason

    public init(
        subject: FormID,
        reason: Reason
    ) {
        self.subject = subject
        self.reason = reason
    }
}

/// One renderable worn part: an ARMA model chosen for race + gender.
nonisolated public struct ResolvedBodyPart: Equatable, Sendable {
    nonisolated public enum Origin: Equatable, Sendable {
        /// Naked-skin ARMO (NPC_ WNAM or RACE WNAM).
        case skin(FormID)
        /// Outfit piece ARMO reached through DOFT.
        case outfit(FormID)
    }

    public let origin: Origin
    public let armature: FormID
    /// ARMA MOD2 (male) / MOD3 (female) path, relative to Data/.
    public let modelPath: String
    /// ARMA MOD4 (male) or MOD5 (female): what this piece shows on the player's own
    /// arms, or nil when it has no first-person geometry.
    public let firstPersonModelPath: String?
    public let slots: BodySlots
    /// ARMA MO2S/MO3S per-shape textures, already resolved through their TXST.
    public let textureSwaps: [ModelSurfaceOverride.ShapeTextures]
    /// The wearer's skin texture set, for the skin this part shows.
    public var skinTextures: ModelSurfaceOverride.SkinTextures?
    /// The side of a decapitation this part draws; nil draws every partition.
    public var cut: DismemberCut?

    public init(
        origin: Origin, armature: FormID, modelPath: String, firstPersonModelPath: String?,
        slots: BodySlots, textureSwaps: [ModelSurfaceOverride.ShapeTextures] = [],
        skinTextures: ModelSurfaceOverride.SkinTextures? = nil
    ) {
        self.skinTextures = skinTextures
        self.origin = origin
        self.armature = armature
        self.modelPath = modelPath
        self.firstPersonModelPath = firstPersonModelPath
        self.slots = slots
        self.textureSwaps = textureSwaps
    }

    /// The swaps as a model override, or nil when the part keeps its own textures.
    public var surface: ModelSurfaceOverride? {
        guard !textureSwaps.isEmpty || skinTextures != nil else { return nil }
        return ModelSurfaceOverride(
            diffuseTexture: nil, normalTexture: nil, tint: nil, shapes: textureSwaps,
            skinTextures: skinTextures
        )
    }
}

/// One rigid model hung off a named skeleton bone, such as a drawn weapon.
/// `bone` is a Havok rig name from `ActorAttachmentBone`, such as `Weapon` under
/// `NPC R Hand [RHnd]` (docs/engine/actor-resolution.md).
nonisolated public struct ResolvedAttachment: Equatable, Sendable {
    /// WEAP, AMMO, or shield ARMA model path, relative to Data/.
    public let modelPath: String
    /// Havok rig bone the model rides while drawn.
    public let bone: String
    /// The node the pose moves `bone` onto while sheathed; nil stays in the hand.
    public let sheathBone: String?
    /// The model node whose shapes are drawn; nil draws the whole model.
    public let subtree: String?

    public init(
        modelPath: String, bone: String, sheathBone: String? = nil, subtree: String? = nil
    ) {
        self.modelPath = modelPath
        self.bone = bone
        self.sheathBone = sheathBone
        self.subtree = subtree
    }
}
