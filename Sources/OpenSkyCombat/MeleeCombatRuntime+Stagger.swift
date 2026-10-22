// The stagger a landed swing raises on its target's graph, by `StaggerRule`.

import OpenSkyBehavior
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM

extension MeleeCombatRuntime {
    /// Tells the target's graph to stagger when the hit's magnitude passes `fStaggerMin`
    /// and the `iStaggerAttackChance` roll passes.
    ///
    /// `staggerMagnitude` is written before the event so the stagger behavior
    /// reads this hit's magnitude rather than the previous one's, which is the
    /// same write-then-raise order the locomotion bridge uses for every step.
    func stagger(
        _ target: ReferenceKey,
        damage: MeleeDamageResult,
        world: any MeleeCombatWorld
    ) -> Bool {
        guard damage.applied > 0 else { return false }
        let hit = staggerHit(damage: damage, world: world)
        let magnitude = StaggerRule.magnitude(hit, settings: staggers)
        let roll = staggerRandom.percent()
        guard StaggerRule.staggers(magnitude: magnitude, roll: roll, settings: staggers)
        else { return false }
        world.writeCombatVariable(
            .real(magnitude), named: CombatGraphNames.staggerMagnitude
        )
        return world.raiseCombatEvent(CombatGraphNames.staggerStart, on: target)
    }

    private func staggerHit(damage: MeleeDamageResult, world: any MeleeCombatWorld) -> StaggerHit {
        var hit = StaggerHit(weaponStagger: weapon.stagger)
        hit.perkMultiplier = damage.strike.staggerMultiplier
        hit.wasBlocked = damage.wasBlocked
        hit.isPowerBash = strikeKind == .powerBash
        if strikeKind.isBash {
            let source = world.meleeBashSource()
            hit.kind = .bash(shieldRating: source.shieldRating)
            hit.attackerBlockSkill = source.blockSkill
        } else {
            hit.kind = strikeKind == .power ? .power : .swing
        }
        return hit
    }
}
