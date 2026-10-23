// Allies: an actor a spell put under a commander. A player's ally fights the foes
// near the player and otherwise walks after it. Another actor's ally fights through
// its own hostility and walks after its commander between fights. See `CombatAllyRule`.

import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyMagicInterface
import OpenSkyPhysics
import simd

extension CombatLoopRuntime {
    /// Puts `actor` under `commander`.
    public func command(_ actor: ReferenceKey, by commander: ReferenceKey) {
        commanders[actor] = commander
    }

    /// Ends `actor`'s service: its fight and its walk stop.
    public func dismiss(_ actor: ReferenceKey) {
        guard commanders.removeValue(forKey: actor) != nil else { return }
        parkBehavior(of: actor)
        world?.stopCombatMovement(of: actor)
        retireBehavior(of: actor)
    }

    /// The allies of `commander`, in key order.
    public func allies(of commander: ReferenceKey) -> [ReferenceKey] {
        commanders.filter { $0.value == commander }.keys.sorted()
    }

    /// One fixed step of every ally. `budget` is what is left of the engagement cap.
    func driveAllies(
        among actors: [CombatActorObservation],
        foes: [MeleeTarget],
        budget: Int,
        influences: [ReferenceKey: ActorMagicInfluence],
        world: any CombatLoopWorld
    ) {
        let player = world.combatPlayer
        var budget = budget
        for actor in actors where !actor.isDead {
            guard
                let commander = commanders[actor.key],
                influences[actor.key]?.refusesCombat != true,
                let home = commander == player.key
                ? player.feet : actors.first(where: { $0.key == commander })?.feet
            else { continue }
            if
                commander == player.key, budget > 0,
                let foe = CombatAllyRule.foe(for: actor.feet, defending: home, among: foes)
            {
                budget -= 1
                following.removeValue(forKey: actor.key)
                drive(
                    actor: actor, influence: influences[actor.key] ?? .none, target: foe,
                    world: world
                )
                continue
            }
            if behaviors[actor.key]?.isEngaged == true {
                guard commander == player.key else { continue }
                parkBehavior(of: actor.key)
                targets.removeValue(forKey: actor.key)
            }
            let distance = combatAI.followDistance(leaderIsPlayer: commander == player.key)
            follow(actor, to: home, within: distance, world: world)
        }
    }

    /// A walk is asked for again only when the commander has moved on from its end.
    private func follow(
        _ actor: CombatActorObservation, to home: SIMD3<Float>, within distance: Float,
        world: any CombatLoopWorld
    ) {
        guard
            let point = CombatAllyRule.followPoint(
                ally: actor.feet, commander: home, followDistance: distance
            )
        else {
            if following.removeValue(forKey: actor.key) != nil {
                world.stopCombatMovement(of: actor.key)
            }
            return
        }
        if
            let walking = following[actor.key],
            simd_distance(walking, point) < CombatAllyRule.keepDistance
        {
            return
        }
        if world.moveCombatActor(actor.key, to: point) {
            following[actor.key] = point
        }
    }
}
