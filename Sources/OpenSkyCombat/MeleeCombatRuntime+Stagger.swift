// The stagger a landed swing raises on its target's graph.

import OpenSkyBehavior
import OpenSkyFormatsESM

extension MeleeCombatRuntime {
    /// Tells the target's graph to stagger, if the weapon carries any stagger
    /// after the stagger perks and the hit was not blocked away.
    ///
    /// `staggerMagnitude` is written before the event so the stagger behavior
    /// reads this hit's magnitude rather than the previous one's, which is the
    /// same write-then-raise order the locomotion bridge uses for every step.
    func stagger(
        _ target: ReferenceKey,
        damage: MeleeDamageResult,
        world: any MeleeCombatWorld
    ) -> Bool {
        let magnitude = weapon.stagger * damage.strike.staggerMultiplier
        guard magnitude > 0, damage.applied > 0 else { return false }
        world.writeCombatVariable(
            .real(magnitude), named: CombatGraphNames.staggerMagnitude
        )
        return world.raiseCombatEvent(CombatGraphNames.staggerStart, on: target)
    }
}
