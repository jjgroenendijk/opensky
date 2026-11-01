// Reflect Damage: a melee blow can come back to the attacker. UESP
// "Skyrim Mod:Actor_Value_Indices" (163) and "Skyrim:Heavy_Armor" (Reflect Blows).

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

extension CombatCoordinator {
    /// The defender's `Reflect Damage` is a percent chance. A reflected blow does not
    /// spare the defender, and it is the damage after armour and block, so UESP's
    /// "reduced by the defender's armour" holds. The defender counts as the attacker
    /// for difficulty: a player's reflected blow is scaled by "player deals".
    func reflectMeleeDamage(
        _ amount: Float,
        from defender: ReferenceKey,
        to attacker: ReferenceKey
    ) {
        guard
            attacker != defender,
            let chance = world.actorValues(of: defender)?(ActorValueIndex.reflectDamage),
            chance > 0,
            Float(strikeRandom.percent()) < chance
        else { return }
        // `.other`, so the reflected blow cannot reflect again.
        applyHealthDamage(amount, to: attacker, attacker: defender, kind: .other)
    }
}
