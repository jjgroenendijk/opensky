// What a mine and an explosive shot read from the combat world: who can set a mine off,
// the player's roll, and the shooter's skill. See docs/engine/explosions.md#mines.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface

extension CombatProjectileWorldPart {
    /// The player's mine reaches the living hostile actors; an NPC's reaches the player
    /// when the NPC is hostile.
    func mineTriggers(for shooter: ReferenceKey) -> [MeleeTarget] {
        let world = shared.world
        guard shooter == .player else {
            guard
                world.hostility(of: shooter) == .hostile, let player = world.playerAttacker
            else { return [] }
            return [MeleeTarget(key: .player, feet: player.feet, capsule: player.capsule)]
        }
        return world.residentActors()
            .filter { !$0.isDead && world.hostility(of: $0.key) == .hostile }
            .map { MeleeTarget(key: $0.key, feet: $0.feet, capsule: $0.capsule) }
    }

    /// The chance starts at 100 and goes through Calculate Mine Explode Chance.
    func playerSetsOffMine() -> Bool {
        let chance = shared.world.perks.perkModified(
            100, at: .calculateMineExplodeChance, on: .player,
            given: (subjects: PerkEvaluationSubjects(owner: .player), seams: ConditionContext())
        )
        let roll = Float(shared.archeryRandom.percent())
        return MineFuse.playerPasses(chance: chance, roll: roll)
    }

    var projectileIsOutdoors: Bool {
        !shared.world.isInInterior
    }

    func explosiveShotSkill(of shooter: ReferenceKey) -> Float? {
        guard let index = ActorValueIdentity.index(named: "Archery") else { return nil }
        return shared.world.actorValues(of: shooter)?(index)
    }
}
