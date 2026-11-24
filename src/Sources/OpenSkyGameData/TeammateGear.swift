// What a teammate wears after armour or a weapon changes hands with the player: per body
// slot, the held armour with the highest rating. See docs/engine/inventory-equipment.md.

import Foundation
public import OpenSkyFormatsESM

nonisolated extension EquipmentCatalog {
    /// The armour a teammate wears from `held`, in pick order. Slots go low bit first;
    /// in each, the strictly highest rating wins, so a tie keeps the first found, and
    /// clothing scores its rating of 0. A later slot's pick takes off any earlier pick it
    /// overlaps.
    public func teammateArmour(_ held: [FormID]) -> [FormID] {
        var seen: Set<FormID> = []
        let armour = held.filter { seen.insert($0).inserted }.compactMap { id in
            item(id).flatMap { $0.isWornArmour && !$0.occupancy.slots.isEmpty ? (id, $0) : nil }
        }
        var picks: [(id: FormID, item: EquippableItem)] = []
        for bit in 0 ..< UInt32.bitWidth {
            let slot = BodySlots(rawValue: 1 << UInt32(bit))
            var best: (id: FormID, item: EquippableItem)?
            var bestRating = -Float.infinity
            for candidate in armour where candidate.1.occupancy.slots.contains(slot) {
                if candidate.1.rating > bestRating {
                    best = (candidate.0, candidate.1)
                    bestRating = candidate.1.rating
                }
            }
            guard let best, !picks.contains(where: { $0.id == best.id }) else { continue }
            picks.removeAll { $0.item.occupancy.conflicts(with: best.item.occupancy) }
            picks.append(best)
        }
        return picks.map(\.id)
    }

    /// The weapon and its ammunition an NPC holds from `held`, beside `worn` armour.
    public func weaponPicks(
        worn: [FormID], held: [FormID], preference: WeaponPreference? = nil
    ) -> [FormID] {
        let weapons = held
            .filter { item($0).map { $0.isWeapon || $0.occupancy.ammunition } ?? false }
        return carriedPicks(worn: worn, carried: weapons, preference: preference)
    }
}
