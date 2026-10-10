// Actor visual resolution: a template-resolved actor becomes skeleton, skin and
// outfit model paths with body-slot masking, and FaceGen paths. Skin: NPC_ or
// RACE WNAM -> ARMO -> ARMA; outfit: DOFT -> OTFT -> ARMO -> ARMA. A runtime
// equipped set replaces DOFT. A broken chain throws; a missing optional part is
// a reason-tagged skip. See docs/engine/actor-resolution.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

/// Terminal visual-resolution failures.
nonisolated public enum ActorVisualError: Error, Equatable {
    /// RNAM absent after template resolution, or no such RACE record.
    case missingRace(FormID?, npc: FormID)
    /// Neither NPC_ WNAM nor RACE WNAM yields a decodable ARMO.
    case missingSkin(FormID?, npc: FormID)
    /// DOFT chain unusable; `item` is the INAM entry that broke (nil when
    /// the OTFT record itself is missing).
    case brokenOutfitChain(outfit: FormID, item: FormID?, reason: OutfitChainFailure)

    nonisolated public enum OutfitChainFailure: Equatable, Sendable {
        case missingOutfitRecord
        /// INAM entry is neither a known ARMO nor a known LVLI.
        case danglingItem
        case emptyLeveledList
        case leveledListCycle
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

    public init(
        origin: Origin, armature: FormID, modelPath: String, firstPersonModelPath: String?,
        slots: BodySlots, textureSwaps: [ModelSurfaceOverride.ShapeTextures] = []
    ) {
        self.origin = origin
        self.armature = armature
        self.modelPath = modelPath
        self.firstPersonModelPath = firstPersonModelPath
        self.slots = slots
        self.textureSwaps = textureSwaps
    }

    /// The swaps as a model override, or nil when the part keeps its own textures.
    public var surface: ModelSurfaceOverride? {
        guard !textureSwaps.isEmpty else { return nil }
        return ModelSurfaceOverride(
            diffuseTexture: nil, normalTexture: nil, tint: nil, shapes: textureSwaps
        )
    }
}

/// One rigid model hung off a named skeleton bone, such as a drawn weapon.
/// `bone` is a Havok rig name from `ActorAttachmentBone`, such as `Weapon` under
/// `NPC R Hand [RHnd]` (docs/engine/actor-resolution.md).
nonisolated public struct ResolvedAttachment: Equatable, Sendable {
    /// WEAP MODL path, relative to Data/.
    public let modelPath: String
    /// Havok rig bone the model rides while drawn.
    public let bone: String
    /// The node the pose moves `bone` onto while sheathed; nil stays in the hand.
    public let sheathBone: String?

    public init(modelPath: String, bone: String, sheathBone: String? = nil) {
        self.modelPath = modelPath
        self.bone = bone
        self.sheathBone = sheathBone
    }
}

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
    /// Rigid bone attachments — drawn weapons. Empty unless a runtime equipped
    /// set supplied one.
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
}

nonisolated extension ResolvedActorVisual {
    /// The visual with a runtime presentation applied: the head source.
    public func presenting(_ state: ActorPresentationState?) -> ResolvedActorVisual {
        guard let state else { return self }
        var copy = self
        copy.headSource = state.headSource
        return copy
    }
}

/// FaceGen paths: the defining plugin's lowercased name, then the 8-hex object ID
/// (docs/formats/actors.md).
nonisolated public enum FaceGenPaths: Sendable {
    public static func mesh(for id: ResolvedFormID) -> String {
        "meshes\\actors\\character\\facegendata\\facegeom\\"
            + component(for: id) + ".nif"
    }

    public static func tint(for id: ResolvedFormID) -> String {
        "textures\\actors\\character\\facegendata\\facetint\\"
            + component(for: id) + ".dds"
    }

    private static func component(for id: ResolvedFormID) -> String {
        id.plugin.lowercased() + "\\" + String(format: "%08x", id.objectID)
    }
}

/// Resolves visuals against pre-built single-plugin record indexes
/// (raw-FormID keys, matching ActorTemplateResolver's convention).
nonisolated public struct ActorVisualResolver: Sendable {
    public let races: [UInt32: Race]
    public let armors: [UInt32: Armor]
    public let armorAddons: [UInt32: ArmorAddon]
    public let outfits: [UInt32: Outfit]
    public let leveledItems: [UInt32: LeveledList]
    /// Maps record FormIDs to (defining plugin, objectID) for FaceGen.
    public let formIDResolver: FormIDResolver
    /// Slot and model data for runtime-equipped items.
    public let equipment: EquipmentCatalog
    /// HDPT records named by NPC_ and RACE head-part lists. Only the expression TRI
    /// fields are decoded.
    public let headParts: [UInt32: HeadPart]
    /// FLST, TXST, and CLFM records the assembled head reads.
    public let formLists: [UInt32: FormList]
    public let textureSets: [UInt32: TextureSet]
    public let colors: [UInt32: ColorForm]
    /// Records `build` could not decode; they resolve as dangling.
    public private(set) var skippedRecords = SkippedRecords()

    public init(
        races: [UInt32: Race],
        armors: [UInt32: Armor],
        armorAddons: [UInt32: ArmorAddon],
        outfits: [UInt32: Outfit],
        leveledItems: [UInt32: LeveledList],
        formIDResolver: FormIDResolver,
        equipment: EquipmentCatalog = EquipmentCatalog(items: [:]),
        headParts: [UInt32: HeadPart] = [:],
        formLists: [UInt32: FormList] = [:],
        textureSets: [UInt32: TextureSet] = [:],
        colors: [UInt32: ColorForm] = [:]
    ) {
        self.races = races
        self.armors = armors
        self.armorAddons = armorAddons
        self.outfits = outfits
        self.leveledItems = leveledItems
        self.formIDResolver = formIDResolver
        self.equipment = equipment
        self.headParts = headParts
        self.formLists = formLists
        self.textureSets = textureSets
        self.colors = colors
    }

    public static func build(
        from file: ESMFile,
        localized _: Bool,
        pluginName: String
    ) -> ActorVisualResolver {
        build(from: LoadOrderPlugins(file: file, name: pluginName))
    }

    /// Indexes every plugin's decodable RACE/ARMO/ARMA/OTFT/LVLI/HDPT records;
    /// a later override wins.
    public static func build(from loadOrder: LoadOrderPlugins) -> ActorVisualResolver {
        var skipped = SkippedRecords()
        var resolver = ActorVisualResolver(
            races: loadOrder.indexRecords(of: "RACE", skipped: &skipped) {
                try Race(record: $0, localized: $1)
            },
            armors: loadOrder.indexRecords(of: "ARMO", skipped: &skipped) {
                try Armor(record: $0, localized: $1)
            },
            armorAddons: loadOrder.indexRecords(of: "ARMA", skipped: &skipped) {
                try ArmorAddon(record: $0)
            },
            outfits: loadOrder
                .indexRecords(of: "OTFT", skipped: &skipped) { try Outfit(record: $0) },
            leveledItems: loadOrder.indexRecords(of: "LVLI", skipped: &skipped) {
                try LeveledList(record: $0)
            },
            formIDResolver: loadOrder.space,
            equipment: EquipmentCatalog.build(from: loadOrder),
            headParts: loadOrder.indexRecords(of: "HDPT", skipped: &skipped) {
                try HeadPart(record: $0, localized: $1)
            },
            formLists: loadOrder.indexRecords(of: "FLST", skipped: &skipped) {
                try FormList(record: $0)
            },
            textureSets: loadOrder.indexRecords(of: "TXST", skipped: &skipped) {
                try TextureSet(record: $0)
            },
            colors: loadOrder.indexRecords(of: "CLFM", skipped: &skipped) {
                try ColorForm(record: $0, localized: $1)
            }
        )
        resolver.skippedRecords = skipped
        return resolver
    }

    /// One actor's renderable inputs.
    /// - Parameters:
    ///   - appearance: the template-resolved actor.
    ///   - equipped: a runtime equipped set that replaces the `defaultOutfit` chain;
    ///     nil resolves through DOFT.
    public func resolve(
        appearance: ResolvedActorAppearance,
        equipped: [FormID]? = nil
    ) throws -> ResolvedActorVisual {
        guard
            let raceID = appearance.race.value,
            let race = races[raceID.rawValue]
        else {
            throw ActorVisualError.missingRace(appearance.race.value, npc: appearance.base)
        }
        var skips: [AppearanceSkip] = []
        let female = appearance.isFemale.value
        let skeletonPath = female ? race.femaleSkeletonPath : race.maleSkeletonPath
        if skeletonPath == nil {
            skips.append(AppearanceSkip(subject: race.formID, reason: .noSkeletonForGender))
        }

        let worn: WornEquipment = if let equipped {
            wornEquipment(equipped: equipped, skips: &skips)
        } else {
            try WornEquipment(armors: outfitPieces(of: appearance))
        }
        let equippedSlots = Self.slotMask(of: worn.armors, skips: &skips)
        var seenArmatures: Set<UInt32> = []
        var parts = wornParts(
            worn.armors, race: raceID, female: female, seen: &seenArmatures, skips: &skips
        )

        let skinID = appearance.wornArmor.value ?? race.defaultSkin
        guard let skinID, let skin = armors[skinID.rawValue] else {
            throw ActorVisualError.missingSkin(skinID, npc: appearance.base)
        }
        let skinSelection = PartSelection(
            origin: .skin(skin.formID), race: raceID, female: female, mask: equippedSlots
        )
        // Skin armatures append after the ordered worn parts rather than
        // sorting among them: the naked body is priority 0, so ordering would
        // put it first, and what actually decides whether covered skin renders
        // at all is the equipped-slot mask above.
        parts += bodyParts(
            of: skin, selection: skinSelection, seen: &seenArmatures, skips: &skips
        ).map(\.part)

        // FaceGen assets belong to the NPC_ that provides character-gen data
        // — the traits source (head parts ride the traits flag). Gated on
        // the RACE FaceGen-head flag: creature races bake no facegeom, and
        // head-part-less humanoids (e.g. Nazeem) still do.
        let face = race.flags.contains(.faceGenHead)
            ? formIDResolver.resolve(appearance.headParts.source)
            : nil
        var visual = ResolvedActorVisual(
            appearance: appearance,
            skeletonPath: skeletonPath,
            skin: skinID,
            equippedSlots: equippedSlots,
            parts: parts,
            attachments: worn.attachments,
            usesRuntimeEquipment: equipped != nil,
            faceGenMeshPath: face.map(FaceGenPaths.mesh(for:)),
            faceGenTintPath: face.map(FaceGenPaths.tint(for:)),
            skips: skips
        )
        if race.flags.contains(.faceGenHead) {
            visual.headParts = headPartResolver.resolve(
                raceDefaults: female ? race.femaleHeadParts : race.maleHeadParts,
                npcParts: appearance.headParts.value,
                race: raceID,
                hairColor: appearance.hairColor.value
            )
        }
        return visual
    }

    /// Expression-bearing HDPT records for one resolved actor. RACE supplies
    /// the default head and mouth; NPC_ head parts supply the chosen eyes,
    /// brows, hair, facial hair and marks. FormID order stays deterministic.
    public func expressionHeadParts(for appearance: ResolvedActorAppearance) -> [HeadPart] {
        guard
            let raceID = appearance.race.value,
            let race = races[raceID.rawValue]
        else { return [] }
        let defaults = appearance.isFemale.value
            ? race.femaleHeadParts : race.maleHeadParts
        var seen = Set<UInt32>()
        return (defaults + appearance.headParts.value).compactMap { id in
            guard seen.insert(id.rawValue).inserted else { return nil }
            guard let part = headParts[id.rawValue], part.expressionMorphPath != nil else {
                return nil
            }
            return part
        }
    }

    /// The union of worn ARMO body slots — the mask that hides covered skin.
    /// An ARMO with no BOD2/BODT contributes nothing and says so.
    private static func slotMask(
        of armors: [Armor],
        skips: inout [AppearanceSkip]
    ) -> BodySlots {
        var mask = BodySlots()
        for armor in armors {
            if let slots = armor.bodyTemplate?.slots {
                mask.formUnion(slots)
            } else {
                skips.append(AppearanceSkip(subject: armor.formID, reason: .missingBodySlots))
            }
        }
        return mask
    }

    /// Every worn piece's race-compatible armatures, in ARMA DNAM draw order.
    private func wornParts(
        _ armors: [Armor],
        race: FormID,
        female: Bool,
        seen: inout Set<UInt32>,
        skips: inout [AppearanceSkip]
    ) -> [ResolvedBodyPart] {
        var candidates: [PrioritizedPart] = []
        for armor in armors {
            let selection = PartSelection(
                origin: .outfit(armor.formID), race: race, female: female, mask: nil
            )
            candidates += bodyParts(
                of: armor, selection: selection, seen: &seen, skips: &skips
            )
        }
        return Self.inDrawOrder(candidates)
    }

    /// Selection inputs shared by every armature of one ARMO. `mask`
    /// non-nil marks skin resolution: armatures overlapping the equipped
    /// slots are hidden instead of emitted.
    public struct PartSelection: Sendable {
        public let origin: ResolvedBodyPart.Origin
        public let race: FormID
        public let female: Bool
        public let mask: BodySlots?
    }

    /// Race-compatible armatures of one ARMO resolved to gendered model
    /// paths, each tagged with the ARMA DNAM draw priority arbitration needs.
    public func bodyParts(
        of armor: Armor,
        selection: PartSelection,
        seen: inout Set<UInt32>,
        skips: inout [AppearanceSkip]
    ) -> [PrioritizedPart] {
        var parts: [PrioritizedPart] = []
        var anyCompatible = false
        for armatureID in armor.armatures {
            guard let armature = armorAddons[armatureID.rawValue] else {
                skips.append(AppearanceSkip(subject: armatureID, reason: .danglingArmature))
                continue
            }
            guard
                armature.primaryRace == selection.race
                || armature.additionalRaces.contains(selection.race)
            else { continue }
            anyCompatible = true
            // ARMA slots decide masking; fall back to the owning ARMO's
            // slots when the armature has no body template of its own.
            let slots = armature.bodyTemplate?.slots
                ?? armor.bodyTemplate?.slots
                ?? BodySlots()
            if let mask = selection.mask, slots.overlaps(mask) {
                skips.append(AppearanceSkip(subject: armatureID, reason: .maskedByOutfit))
                continue
            }
            guard seen.insert(armatureID.rawValue).inserted else {
                skips.append(AppearanceSkip(subject: armatureID, reason: .duplicateArmature))
                continue
            }
            // Gendered model with cross-gender fallback: many vanilla ARMAs
            // carry only MOD2 and the game shows it on both genders
            // (e.g. StormCloakBootsAA) — skip only when neither exists.
            let preferred = selection.female
                ? armature.femaleModelPath
                : armature.maleModelPath
            guard let path = preferred ?? armature.maleModelPath ?? armature.femaleModelPath
            else {
                skips.append(AppearanceSkip(subject: armatureID, reason: .noModel))
                continue
            }
            parts.append(PrioritizedPart(
                part: ResolvedBodyPart(
                    origin: selection.origin, armature: armatureID,
                    modelPath: path,
                    firstPersonModelPath: armature.firstPersonModelPath(
                        female: selection.female
                    ),
                    slots: slots,
                    textureSwaps: textureSwaps(of: armature, female: selection.female)
                ),
                priority: armature.priority(female: selection.female)
            ))
        }
        if !anyCompatible {
            skips.append(AppearanceSkip(subject: armor.formID, reason: .noCompatibleArmature))
        }
        return parts
    }
}

nonisolated extension ActorVisualResolver {
    public var headPartResolver: HeadPartResolver {
        HeadPartResolver(
            headParts: headParts, formLists: formLists, textureSets: textureSets, colors: colors
        )
    }
}
