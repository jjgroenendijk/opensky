// An arrow that strikes a destructible object damages it through the combat world.
// See docs/engine/papyrus-destruction.md#in-the-game.

import OpenSkyFormatsESM

extension CombatProjectileWorldPart {
    func applyProjectileDestruction(_ amount: Float, to reference: FormID) -> Bool {
        guard let key = shared.world.destructibleKey(reference: reference) else { return false }
        return shared.world.damageDestructible(key, amount: amount)
    }
}
