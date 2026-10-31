// What an NPC wears with no runtime equipped set: its outfit, plus the weapon and
// armour it picks from its carried items. A worn shield rides a hand node, because
// its model is rigid and has no skin. See docs/engine/actor-resolution.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

/// What an NPC carries: its `CNTO` entries, and the combat style (`ZNAM`) that
/// weighs a melee weapon against a bow.
nonisolated public struct CarriedItems: Sendable {
    public static let none = CarriedItems(entries: [], combatStyle: nil)

    public let entries: [Container.Entry]
    public let combatStyle: FormID?

    public init(entries: [Container.Entry], combatStyle: FormID?) {
        self.entries = entries
        self.combatStyle = combatStyle
    }
}

nonisolated extension ActorVisualResolver {
    /// Deepest leveled-list nesting a carried entry follows, as the inventory baseline.
    static let maximumCarriedDepth = 8

    /// The outfit, then the carried items `EquipmentCatalog.carriedPicks` chooses.
    /// Leveled entries roll as the inventory baseline rolls them.
    func defaultEquipment(
        of appearance: ResolvedActorAppearance,
        roll: LeveledRoll?,
        carried: CarriedItems,
        skips: inout [AppearanceSkip]
    ) throws -> WornEquipment {
        let outfit = try outfitPieces(of: appearance, roll: roll)
        guard !carried.entries.isEmpty else { return WornEquipment(armors: outfit) }
        let actorRoll = roll ?? leveling.roll(forActor: appearance.base)
        var items: [FormID] = []
        for entry in carried.entries where entry.count >= 1 {
            appendCarried(entry.item, count: entry.count, roll: actorRoll, depth: 0, into: &items)
        }
        let preference = carried.combatStyle
            .flatMap { combatStyles[$0.rawValue] }
            .map(WeaponPreference.init(style:))
        let picks = equipment.carriedPicks(
            worn: outfit.map(\.formID), carried: items, preference: preference
        )
        let extra = wornEquipment(equipped: picks, skips: &skips)
        return WornEquipment(armors: outfit + extra.armors, attachments: extra.attachments)
    }

    private func appendCarried(
        _ id: FormID, count: Int32, roll: LeveledRoll, depth: Int, into items: inout [FormID]
    ) {
        guard depth < Self.maximumCarriedDepth, let list = leveledItems[id.rawValue] else {
            items.append(id)
            return
        }
        for pick in leveling.roll(list, count: count, request: roll.request, seed: roll.seed) {
            appendCarried(
                pick.entry.reference, count: pick.count, roll: roll, depth: depth + 1, into: &items
            )
        }
    }

    /// Splits worn parts into body parts and held armour. A shield takes a hand, so
    /// it rides the left-hand `Shield` node as a weapon rides `Weapon`.
    func heldArmour(
        _ parts: [ResolvedBodyPart]
    ) -> (parts: [ResolvedBodyPart], attachments: [ResolvedAttachment]) {
        var body: [ResolvedBodyPart] = []
        var held: [ResolvedAttachment] = []
        for part in parts {
            guard
                case let .outfit(armor) = part.origin,
                !equipment.occupancy(of: armor).hands.isEmpty
            else {
                body.append(part)
                continue
            }
            held.append(ResolvedAttachment(
                modelPath: part.modelPath, bone: ActorAttachmentBone.drawnOffHand
            ))
        }
        return (body, held)
    }
}

nonisolated extension ActorTemplateResolver {
    /// The carried items and combat style after templates. A broken chain carries
    /// nothing; the appearance path already reports it.
    public func carriedItems(base: FormID) -> CarriedItems {
        CarriedItems(
            entries: (try? resolveCarriedItems(base: base).value) ?? [],
            combatStyle: (try? resolveCombatStyle(base: base))?.value
        )
    }
}
