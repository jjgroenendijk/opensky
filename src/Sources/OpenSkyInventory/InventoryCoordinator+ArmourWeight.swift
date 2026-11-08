// Worn armour at its Mod Armor Weight value: Conditioning and Unhindered make worn
// armour weigh nothing. The carried total and the detection noise both read it.
// See docs/engine/perk-entry-points.md.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface

/// One worn armour piece: its record weight and what the wearer's perks make of it.
nonisolated public struct WornArmourWeight: Equatable, Sendable {
    public let authored: Float
    public let worn: Float

    public init(authored: Float, worn: Float) {
        self.authored = authored
        self.worn = worn
    }
}

extension InventoryCoordinator {
    /// What the player carries, with worn armour at its perk weight.
    public var playerCarriedWeight: Float {
        guard let runtime else { return 0 }
        let saved = wornArmourWeights().reduce(0) { $0 + $1.authored - $1.worn }
        return max(0, runtime.inventory.carriedWeight(of: runtime.player) - saved)
    }

    /// The weight of the armour the player wears, after perks. UESP counts armour
    /// only in movement noise; a carried sword makes none.
    public var playerWornArmourWeight: Float {
        wornArmourWeights().reduce(0) { $0 + $1.worn }
    }

    func wornArmourWeights() -> [WornArmourWeight] {
        guard let runtime else { return [] }
        let items = runtime.inventory.baselines.items
        return runtime.inventory.inventory(of: runtime.player).equipped.compactMap { item in
            guard let definition = items.definition(item), definition.family == .armor else {
                return nil
            }
            let authored = max(0, definition.weight)
            let worn = world.perkModified(
                authored,
                at: .modArmorWeight,
                on: .player,
                subjects: PerkEvaluationSubjects(owner: .player)
                    .binding(.item, to: items.conditionSubject(of: item)),
                seams: ConditionContext()
            )
            return WornArmourWeight(authored: authored, worn: max(0, worn))
        }
    }
}
