// What an NPC equips from the items it carries, on top of its outfit. The game
// picks the best item of each kind (UESP Skyrim:Followers, "Follower Equipment").
// A bow or crossbow brings the best matching ammunition.
// See docs/engine/actor-resolution.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

/// How much a combat style favours each kind of weapon: CSTY `CSGD` Equipment Score
/// Mults, which multiply a weapon's damage (Creation Kit wiki "Combat Style").
nonisolated public struct WeaponPreference: Equatable, Sendable {
    public let melee: Float
    public let ranged: Float
    public let staff: Float

    public init(melee: Float, ranged: Float, staff: Float) {
        self.melee = melee
        self.ranged = ranged
        self.staff = staff
    }

    /// A multiplier the record leaves out counts as 1.
    public init(style: CombatStyle) {
        self.init(
            melee: style.value(.meleeScoreMultiplier) ?? 1,
            ranged: style.value(.rangedScoreMultiplier) ?? 1,
            staff: style.value(.staffScoreMultiplier) ?? 1
        )
    }

    func score(_ item: EquippableItem) -> Float {
        switch item.animationType {
        case .bow, .crossbow: item.rating * ranged
        case .staff: item.rating * staff
        default: item.rating * melee
        }
    }
}

nonisolated extension EquipmentCatalog {
    /// The carried items an NPC equips beside `worn`, in pick order. One weapon
    /// that fits the free hands, then armour and a shield in the slots and hands
    /// still free. Within a kind the highest rating wins; a tie keeps carry order.
    public func carriedPicks(
        worn: [FormID], carried: [FormID], preference: WeaponPreference? = nil
    ) -> [FormID] {
        var taken = worn.reduce(into: EquipmentOccupancy.none) {
            $0 = $0.union(occupancy(of: $1))
        }
        let candidates = rankedCandidates(carried, excluding: Set(worn))
        var picks: [FormID] = []
        let fitting = candidates.filter { !$0.item.occupancy.conflicts(with: taken) }
        if let weapon = Self.preferredWeapon(fitting, preference: preference) {
            picks.append(weapon.id)
            taken = taken.union(weapon.item.occupancy)
            if let ammunition = Self.ammunition(for: weapon.item, in: candidates) {
                picks.append(ammunition.id)
                taken = taken.union(ammunition.item.occupancy)
            }
        }
        for candidate in candidates where candidate.item.isWornArmour {
            guard !candidate.item.occupancy.conflicts(with: taken) else { continue }
            picks.append(candidate.id)
            taken = taken.union(candidate.item.occupancy)
        }
        return picks
    }

    private struct Candidate {
        let id: FormID
        let item: EquippableItem
    }

    /// Each equippable carried item once, best first. `enumerated()` keeps the sort stable.
    private func rankedCandidates(_ carried: [FormID], excluding worn: Set<FormID>) -> [Candidate] {
        var seen = worn
        let unique = carried.filter { seen.insert($0).inserted }
        let equippable = unique.enumerated().compactMap { offset, id -> (Int, Candidate)? in
            guard let entry = item(id), !entry.occupancy.isEmpty else { return nil }
            return (offset, Candidate(id: id, item: entry))
        }
        return equippable
            .sorted { lhs, rhs in
                lhs.1.item.rating == rhs.1.item.rating
                    ? lhs.0 < rhs.0
                    : lhs.1.item.rating > rhs.1.item.rating
            }
            .map(\.1)
    }

    /// The highest damage times the style's multiplier. With no style, a melee weapon
    /// comes before a bow, crossbow, or staff. Hand-to-hand is no weapon to hold.
    private static func preferredWeapon(
        _ candidates: [Candidate], preference: WeaponPreference?
    ) -> Candidate? {
        let weapons = candidates.filter {
            $0.item.isWeapon && $0.item.animationType != .other
        }
        guard let preference else {
            return weapons.first { !isSecondary($0.item.animationType) } ?? weapons.first
        }
        var best: Candidate?
        for weapon in weapons {
            if let current = best, preference.score(weapon.item) <= preference.score(current.item) {
                continue
            }
            best = weapon
        }
        return best
    }

    /// The best carried arrows for a bow, or bolts for a crossbow.
    private static func ammunition(
        for weapon: EquippableItem,
        in candidates: [Candidate]
    ) -> Candidate? {
        guard isRanged(weapon.animationType) else { return nil }
        return candidates.first {
            $0.item.occupancy.ammunition && $0.item.animationType == weapon.animationType
        }
    }

    private static func isRanged(_ type: Weapon.AnimationType?) -> Bool {
        type == .bow || type == .crossbow
    }

    private static func isSecondary(_ type: Weapon.AnimationType?) -> Bool {
        switch type {
        case .bow, .crossbow, .staff: true
        default: false
        }
    }
}

nonisolated extension EquipmentOccupancy {
    /// Both items' slots and hands together.
    public func union(_ other: Self) -> Self {
        EquipmentOccupancy(
            slots: slots.union(other.slots),
            hands: hands.union(other.hands),
            ammunition: ammunition || other.ammunition
        )
    }
}

nonisolated extension EquippableItem {
    /// Armour, a shield included: not a weapon, and not ammunition.
    var isWornArmour: Bool {
        !isWeapon && !occupancy.ammunition
    }
}
