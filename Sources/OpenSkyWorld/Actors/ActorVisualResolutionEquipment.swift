// Runtime equipment in visual resolution. The equipped set replaces the DOFT
// chain rather than merging with it. ARMA DNAM priority orders worn parts and
// does not hide them (Orcish boots at 10 draw over the cuirass at 5), so parts
// sort by priority and the BOD2 slot mask does the hiding. A bad equipped FormID
// is a reason-tagged skip. See docs/engine/actor-resolution.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// Skeleton nodes a rigid attachment can hang from, observed with
/// `openskycli skeleton`: `Weapon` under `NPC R Hand [RHnd]` and `Shield` under
/// `NPC L Hand [LHnd]`. See docs/engine/actor-resolution.md.
nonisolated public enum ActorAttachmentBone: Sendable {
    /// The drawn right-hand weapon node.
    public static let drawnWeapon = "Weapon"
}

/// One resolved body part with the ARMA DNAM draw priority that orders it.
nonisolated public struct PrioritizedPart: Equatable, Sendable {
    public let part: ResolvedBodyPart
    /// DNAM priority for the resolved gender. 0 for a DNAM-less ARMA, which
    /// is the naked-body level and therefore sorts first.
    public let priority: UInt8
}

/// The worn pieces one resolve pass drew from, whichever source supplied them.
nonisolated public struct WornEquipment: Sendable {
    public let armors: [Armor]
    public let attachments: [ResolvedAttachment]

    public init(armors: [Armor], attachments: [ResolvedAttachment] = []) {
        self.armors = armors
        self.attachments = attachments
    }
}

nonisolated extension ActorVisualResolver {
    /// DOFT -> OTFT -> INAM entries, each an ARMO or an LVLI expanded via
    /// the deterministic entry policy. Any unusable link throws — the gate
    /// forbids silently rendering the actor naked when the chain breaks.
    public func outfitPieces(of appearance: ResolvedActorAppearance) throws -> [Armor] {
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
    public func wornEquipment(
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
                modelPath: modelPath,
                bone: ActorAttachmentBone.drawnWeapon
            ))
        }
        return WornEquipment(armors: armors, attachments: attachments)
    }

    /// Worn parts in ARMA DNAM draw order: ascending priority, ties in resolve order.
    /// `enumerated()` gives a stable tie-break, since `sorted(by:)` is not stable.
    public static func inDrawOrder(_ parts: [PrioritizedPart]) -> [ResolvedBodyPart] {
        parts.enumerated()
            .sorted { lhs, rhs in
                (lhs.element.priority, lhs.offset) < (rhs.element.priority, rhs.offset)
            }
            .map(\.element.part)
    }
}
