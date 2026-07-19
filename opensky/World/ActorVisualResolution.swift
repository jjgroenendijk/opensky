// Actor visual resolution (milestone 5.2): turn a template-resolved actor
// (ActorResolution.swift) into concrete renderable inputs — per-gender
// skeleton, skin + outfit body-part model paths with body-slot masking, and
// FaceGen head mesh/tint paths.
//
// Chain shapes (UESP NPC_/RACE/ARMO/ARMA/OTFT pages + real-install probe,
// docs/formats/actors.md):
//   skin:   NPC_ WNAM else RACE WNAM -> ARMO -> race-compatible ARMA
//   outfit: NPC_ DOFT -> OTFT INAM (ARMO or LVLI; LVLI expands via the same
//           deterministic entry policy as LVLN) -> ARMO -> ARMA
// Equipped ARMO body slots (BOD2/BODT) union into a mask; a skin armature
// whose slots overlap the mask is hidden — covered skin never renders under
// clothes, so no duplicate geometry.
//
// Failure policy per the milestone gate: a broken chain (dangling FormID,
// empty/cyclic leveled list, missing race/skin/outfit record) throws — never
// a silent naked fallback. Missing optional parts degrade to reason-tagged
// skips so accounting stays exact.

import Foundation

/// Terminal visual-resolution failures.
nonisolated enum ActorVisualError: Error, Equatable {
    /// RNAM absent after template resolution, or no such RACE record.
    case missingRace(FormID?, npc: FormID)
    /// Neither NPC_ WNAM nor RACE WNAM yields a decodable ARMO.
    case missingSkin(FormID?, npc: FormID)
    /// DOFT chain unusable; `item` is the INAM entry that broke (nil when
    /// the OTFT record itself is missing).
    case brokenOutfitChain(outfit: FormID, item: FormID?, reason: OutfitChainFailure)

    nonisolated enum OutfitChainFailure: Equatable {
        case missingOutfitRecord
        /// INAM entry is neither a known ARMO nor a known LVLI.
        case danglingItem
        case emptyLeveledList
        case leveledListCycle
    }
}

/// Reason-tagged degrade: the part is absent from `parts` on purpose, and
/// the reason says why (exact accounting, no silent drops).
nonisolated struct AppearanceSkip: Equatable {
    nonisolated enum Reason: Equatable {
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
    }

    /// The record the skip is about (ARMA, ARMO, or RACE FormID).
    let subject: FormID
    let reason: Reason
}

/// One renderable worn part: an ARMA model chosen for race + gender.
nonisolated struct ResolvedBodyPart: Equatable {
    nonisolated enum Origin: Equatable {
        /// Naked-skin ARMO (NPC_ WNAM or RACE WNAM).
        case skin(FormID)
        /// Outfit piece ARMO reached through DOFT.
        case outfit(FormID)
    }

    let origin: Origin
    let armature: FormID
    /// ARMA MOD2 (male) / MOD3 (female) path, relative to Data/.
    let modelPath: String
    let slots: BodySlots
}

/// Everything milestone 5.2 resolves for one placed actor.
nonisolated struct ResolvedActorVisual: Equatable {
    let appearance: ResolvedActorAppearance
    /// RACE ANAM for the resolved gender; nil -> reason-tagged skip.
    let skeletonPath: String?
    /// The ARMO providing naked skin (after WNAM fallback).
    let skin: FormID
    /// Union of equipped outfit ARMO body slots — the skin mask.
    let equippedSlots: BodySlots
    let parts: [ResolvedBodyPart]
    /// Nil when the race does not use baked FaceGen heads (RACE DATA flag
    /// 0x2 clear — creature races like cow/dog/bear have no facegeom files).
    let faceGenMeshPath: String?
    let faceGenTintPath: String?
    let skips: [AppearanceSkip]
}

/// FaceGen asset path convention, verified against the real install
/// (docs/formats/actors.md): directory is the defining plugin's file name
/// lowercased; file name is the full FormID with the load-order byte zeroed
/// (== 8-hex zero-padded objectID); separators + extension lowercase.
nonisolated enum FaceGenPaths {
    static func mesh(for id: ResolvedFormID) -> String {
        "meshes\\actors\\character\\facegendata\\facegeom\\"
            + component(for: id) + ".nif"
    }

    static func tint(for id: ResolvedFormID) -> String {
        "textures\\actors\\character\\facegendata\\facetint\\"
            + component(for: id) + ".dds"
    }

    private static func component(for id: ResolvedFormID) -> String {
        id.plugin.lowercased() + "\\" + String(format: "%08x", id.objectID)
    }
}

/// Resolves visuals against pre-built single-plugin record indexes
/// (raw-FormID keys, matching ActorTemplateResolver's convention).
nonisolated struct ActorVisualResolver {
    let races: [UInt32: Race]
    let armors: [UInt32: Armor]
    let armorAddons: [UInt32: ArmorAddon]
    let outfits: [UInt32: Outfit]
    let leveledItems: [UInt32: LeveledList]
    /// Maps record FormIDs to (defining plugin, objectID) for FaceGen.
    let formIDResolver: FormIDResolver

    /// Indexes every decodable RACE/ARMO/ARMA/OTFT/LVLI top-group record.
    /// Undecodable records drop out and later resolve as dangling.
    static func build(
        from file: ESMFile,
        localized: Bool,
        pluginName: String
    ) -> ActorVisualResolver {
        let masters = (try? file.pluginHeader().masters) ?? []
        return ActorVisualResolver(
            races: index(file, "RACE") { try Race(record: $0, localized: localized) },
            armors: index(file, "ARMO") { try Armor(record: $0, localized: localized) },
            armorAddons: index(file, "ARMA") { try ArmorAddon(record: $0) },
            outfits: index(file, "OTFT") { try Outfit(record: $0) },
            leveledItems: index(file, "LVLI") { try LeveledList(record: $0) },
            formIDResolver: FormIDResolver(pluginName: pluginName, masters: masters)
        )
    }

    private static func index<Value>(
        _ file: ESMFile,
        _ type: FourCC,
        _ decode: (ESMRecord) throws -> Value
    ) -> [UInt32: Value] {
        var values: [UInt32: Value] = [:]
        guard let top = file.topGroup(of: type), let children = try? top.children() else {
            return values
        }
        for case let .record(record) in children {
            guard record.type == type, !record.isDeleted else { continue }
            values[record.formID] = try? decode(record)
        }
        return values
    }

    func resolve(appearance: ResolvedActorAppearance) throws -> ResolvedActorVisual {
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

        let outfitArmors = try outfitPieces(of: appearance)
        var equippedSlots = BodySlots()
        for armor in outfitArmors {
            if let slots = armor.bodyTemplate?.slots {
                equippedSlots.formUnion(slots)
            } else {
                skips.append(AppearanceSkip(subject: armor.formID, reason: .missingBodySlots))
            }
        }

        var parts: [ResolvedBodyPart] = []
        var seenArmatures: Set<UInt32> = []
        for armor in outfitArmors {
            let selection = PartSelection(
                origin: .outfit(armor.formID), race: raceID, female: female, mask: nil
            )
            parts += bodyParts(
                of: armor, selection: selection, seen: &seenArmatures, skips: &skips
            )
        }

        let skinID = appearance.wornArmor.value ?? race.defaultSkin
        guard let skinID, let skin = armors[skinID.rawValue] else {
            throw ActorVisualError.missingSkin(skinID, npc: appearance.base)
        }
        let skinSelection = PartSelection(
            origin: .skin(skin.formID), race: raceID, female: female, mask: equippedSlots
        )
        parts += bodyParts(
            of: skin, selection: skinSelection, seen: &seenArmatures, skips: &skips
        )

        // FaceGen assets belong to the NPC_ that provides character-gen data
        // — the traits source (head parts ride the traits flag). Gated on
        // the RACE FaceGen-head flag: creature races bake no facegeom, and
        // head-part-less humanoids (e.g. Nazeem) still do.
        let face = race.flags.contains(.faceGenHead)
            ? formIDResolver.resolve(appearance.headParts.source)
            : nil
        return ResolvedActorVisual(
            appearance: appearance,
            skeletonPath: skeletonPath,
            skin: skinID,
            equippedSlots: equippedSlots,
            parts: parts,
            faceGenMeshPath: face.map(FaceGenPaths.mesh(for:)),
            faceGenTintPath: face.map(FaceGenPaths.tint(for:)),
            skips: skips
        )
    }

    /// DOFT -> OTFT -> INAM entries, each an ARMO or an LVLI expanded via
    /// the deterministic entry policy. Any unusable link throws — the gate
    /// forbids silently rendering the actor naked when the chain breaks.
    private func outfitPieces(of appearance: ResolvedActorAppearance) throws -> [Armor] {
        guard let outfitID = appearance.defaultOutfit.value else { return [] }
        guard let outfit = outfits[outfitID.rawValue] else {
            throw ActorVisualError.brokenOutfitChain(
                outfit: outfitID, item: nil, reason: .missingOutfitRecord
            )
        }
        var pieces: [Armor] = []
        for item in outfit.items {
            var ancestors: Set<UInt32> = []
            try appendPieces(
                item: item, outfit: outfitID, ancestors: &ancestors, into: &pieces
            )
        }
        return pieces
    }

    /// One INAM entry: an ARMO directly, or an LVLI — a `useAll` list is a
    /// bundle (every entry equips, e.g. ArmorStormcloakSet), any other list
    /// picks its deterministic entry. `ancestors` tracks only the active
    /// chain so duplicate siblings stay legal while cycles throw.
    private func appendPieces(
        item: FormID,
        outfit: FormID,
        ancestors: inout Set<UInt32>,
        into pieces: inout [Armor]
    ) throws {
        if let armor = armors[item.rawValue] {
            pieces.append(armor)
            return
        }
        guard let list = leveledItems[item.rawValue] else {
            throw ActorVisualError.brokenOutfitChain(
                outfit: outfit, item: item, reason: .danglingItem
            )
        }
        guard ancestors.insert(item.rawValue).inserted else {
            throw ActorVisualError.brokenOutfitChain(
                outfit: outfit, item: item, reason: .leveledListCycle
            )
        }
        defer { ancestors.remove(item.rawValue) }
        if list.flags.contains(.useAll) {
            guard !list.entries.isEmpty else {
                throw ActorVisualError.brokenOutfitChain(
                    outfit: outfit, item: item, reason: .emptyLeveledList
                )
            }
            for entry in list.entries {
                try appendPieces(
                    item: entry.reference, outfit: outfit,
                    ancestors: &ancestors, into: &pieces
                )
            }
        } else {
            guard let entry = list.deterministicEntry else {
                throw ActorVisualError.brokenOutfitChain(
                    outfit: outfit, item: item, reason: .emptyLeveledList
                )
            }
            try appendPieces(
                item: entry.reference, outfit: outfit,
                ancestors: &ancestors, into: &pieces
            )
        }
    }

    /// Selection inputs shared by every armature of one ARMO. `mask`
    /// non-nil marks skin resolution: armatures overlapping the equipped
    /// slots are hidden instead of emitted.
    private struct PartSelection {
        let origin: ResolvedBodyPart.Origin
        let race: FormID
        let female: Bool
        let mask: BodySlots?
    }

    /// Race-compatible armatures of one ARMO resolved to gendered model
    /// paths.
    private func bodyParts(
        of armor: Armor,
        selection: PartSelection,
        seen: inout Set<UInt32>,
        skips: inout [AppearanceSkip]
    ) -> [ResolvedBodyPart] {
        var parts: [ResolvedBodyPart] = []
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
            parts.append(ResolvedBodyPart(
                origin: selection.origin, armature: armatureID,
                modelPath: path, slots: slots
            ))
        }
        if !anyCompatible {
            skips.append(AppearanceSkip(subject: armor.formID, reason: .noCompatibleArmature))
        }
        return parts
    }
}
