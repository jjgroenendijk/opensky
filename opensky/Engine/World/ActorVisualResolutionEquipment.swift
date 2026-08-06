// Runtime equipment in visual resolution (issue #178, roadmap item 12.2.1),
// split from ActorVisualResolution.swift for file-length limits.
//
// Two things live here, both of which only matter once something can equip.
//
// The first is the equipped-set override. An actor whose inventory component
// exists resolves its worn armour from `ReferenceInventoryState.equipped`
// instead of from the plugin `defaultOutfit` chain — a wholesale replacement,
// not a merge, because the baseline equipped set already *is* the default
// outfit (`InventoryBaselineResolver.actorBaseline`). Merging the two would
// re-dress an actor the moment anything undressed it. Everything downstream is
// unchanged: the same body-slot mask hides covered skin, the same ARMA
// selection picks gendered models, and refresh is the normal
// `noteStateMutation` cell rebuild.
//
// The second is ARMA DNAM draw priority. It orders worn parts; it does not
// hide them. That distinction was settled against the install rather than
// assumed, and the first reading here was wrong in a way worth recording:
//
//     openskycli record OrcishCuirassAA
//       -> slots 0x114 (body|forearms|calves), priority male 5 female 5
//     openskycli record OrcishBootsAA
//       -> slots 0x180 (feet|calves),          priority male 10 female 10
//
// The two share the calves slot, and the boots outrank the cuirass there. Were
// priority a visibility rule, equipping Orcish boots would delete the Orcish
// cuirass — one armature covers body, forearms *and* calves, so hiding it for
// losing one slot takes the torso with it. Vanilla plainly draws both. The
// Creation Kit wiki says as much once read precisely: priority "is used to
// determine the order of the ArmorAddons", with the naked body at 0, a torso
// at 5, and "gloves that you want to draw over the ends of sleeves" at 10 —
// an ordering, and the same 5-then-10 the records above carry.
//
// So parts sort by ascending priority, stably, and the highest-priority
// armature is emitted last. Hiding stays the job of the equipped-slot mask,
// which has better evidence for it: an ARMO's own BOD2 slots. Within one
// actor's equipped set that is also sufficient, because `EquipmentRuntime`
// already refuses to equip two pieces claiming the same biped slot, so no two
// worn armatures can contest a slot in the first place.
//
// A runtime equipped set never throws. A broken DOFT chain is malformed plugin
// data and the milestone gate says throw; an equipped FormID that names
// nothing renderable is ordinary runtime state — a dropped-in mod item, a
// script equipping a token — and degrades to a reason-tagged skip.
//
// Documented in docs/formats/actors.md.

import Foundation

/// Skeleton nodes a rigid attachment can hang from.
///
/// Observed from the vanilla character rig rather than recalled: probing
/// `meshes\actors\character\character assets\skeleton.hkx` with
/// `openskycli skeleton` shows bone 43 `Weapon` parented to bone 39
/// `NPC R Hand [RHnd]`, and bone 42 `Shield` parented to `NPC L Hand [LHnd]`.
/// The sheathed nodes (`WeaponSword`, `WeaponAxe`, `WeaponBack`, `Quiver`)
/// hang off the pelvis and spine instead and belong to draw/sheath, which is
/// M15. Recorded in docs/formats/actors.md.
nonisolated enum ActorAttachmentBone {
    /// The drawn right-hand weapon node.
    static let drawnWeapon = "Weapon"
}

/// One resolved body part with the ARMA DNAM draw priority that orders it.
nonisolated struct PrioritizedPart: Equatable {
    let part: ResolvedBodyPart
    /// The ARMO the armature came from — carried for logging and tests, so a
    /// part's provenance survives the sort.
    let owner: FormID
    /// DNAM priority for the resolved gender. 0 for a DNAM-less ARMA, which
    /// is the naked-body level and therefore sorts first.
    let priority: UInt8
}

/// The worn pieces one resolve pass drew from, whichever source supplied them.
nonisolated struct WornEquipment {
    let armors: [Armor]
    let attachments: [ResolvedAttachment]

    init(armors: [Armor], attachments: [ResolvedAttachment] = []) {
        self.armors = armors
        self.attachments = attachments
    }
}

nonisolated extension ActorVisualResolver {
    /// DOFT -> OTFT -> INAM entries, each an ARMO or an LVLI expanded via
    /// the deterministic entry policy. Any unusable link throws — the gate
    /// forbids silently rendering the actor naked when the chain breaks.
    func outfitPieces(of appearance: ResolvedActorAppearance) throws -> [Armor] {
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

    /// Splits a runtime equipped set into worn armour and hand attachments.
    ///
    /// Order follows the equipped set, which `ReferenceInventoryState` keeps
    /// sorted by FormID — so two stores that reached the same equipped set
    /// resolve to the same part list in the same order.
    func wornEquipment(
        equipped: [FormID],
        skips: inout [AppearanceSkip]
    ) -> WornEquipment {
        var armors: [Armor] = []
        var attachments: [ResolvedAttachment] = []
        for item in equipped {
            if let armor = self.armors[item.rawValue] {
                armors.append(armor)
                continue
            }
            guard
                let entry = equipment.item(item),
                !entry.occupancy.hands.isEmpty,
                let modelPath = entry.modelPath
            else {
                skips.append(AppearanceSkip(subject: item, reason: .unrenderableEquipment))
                continue
            }
            attachments.append(ResolvedAttachment(
                item: item,
                modelPath: modelPath,
                bone: ActorAttachmentBone.drawnWeapon
            ))
        }
        return WornEquipment(armors: armors, attachments: attachments)
    }

    /// Worn parts in ARMA DNAM draw order: ascending priority, ties left in
    /// the order the pieces resolved in.
    ///
    /// The sort is stable — `enumerated()` supplies the index as the tie-break
    /// rather than relying on `sorted(by:)`, which Swift does not guarantee to
    /// be stable — so an outfit whose ARMAs all carry the same priority comes
    /// out in exactly the order it went in, and nothing about the existing
    /// plugin-outfit path moves.
    static func inDrawOrder(_ parts: [PrioritizedPart]) -> [ResolvedBodyPart] {
        parts.enumerated()
            .sorted { lhs, rhs in
                (lhs.element.priority, lhs.offset) < (rhs.element.priority, rhs.offset)
            }
            .map(\.element.part)
    }
}
