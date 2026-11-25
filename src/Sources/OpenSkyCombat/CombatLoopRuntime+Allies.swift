// Allies: an actor a spell put under a commander. A player's ally fights the foes
// near the player and otherwise walks after it. Another actor's ally fights through
// its own hostility and walks after its commander between fights. See `CombatAllyRule`.

import OpenSkyCombatInterface
public import OpenSkyFormatsESM
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
    func allies(of commander: ReferenceKey) -> [ReferenceKey] {
        commanders.filter { $0.value == commander }.keys.sorted()
    }

    /// One fixed step of every ally. `budget` is what is left of the engagement cap.
    func driveAllies(
        among actors: [CombatActorObservation],
        engaging: (foes: [MeleeTarget], budget: Int),
        influences: [ReferenceKey: ActorMagicInfluence],
        world: any CombatLoopWorld
    ) {
        AllyDrive(owner: self).driveAllies(
            among: actors,
            engaging: engaging,
            influences: influences,
            world: world
        )
    }
}

extension CombatLoopRuntime {
    /// Drives the player's allies in a fight.
    struct AllyDrive {
        let owner: CombatLoopRuntime

        func driveAllies(
            among actors: [CombatActorObservation],
            engaging: (foes: [MeleeTarget], budget: Int),
            influences: [ReferenceKey: ActorMagicInfluence],
            world: any CombatLoopWorld
        ) {
            let player = world.combatPlayer
            let foes = engaging.foes.filter { !world.combatIsChild($0.key) }
            var budget = engaging.budget
            for actor in actors where !actor.isDead {
                guard
                    let commander = owner.commanders[actor.key],
                    influences[actor.key]?.refusesCombat != true,
                    let home = commander == player.key
                    ? player.feet : actors.first(where: { $0.key == commander })?.feet
                else { continue }
                if
                    commander == player.key, budget > 0,
                    let foe = CombatAllyRule.foe(for: actor.feet, defending: home, among: foes)
                {
                    budget -= 1
                    owner.following.removeValue(forKey: actor.key)
                    owner.drive(
                        actor: actor, influence: influences[actor.key] ?? .none, target: foe,
                        world: world
                    )
                    continue
                }
                if owner.behaviors[actor.key]?.isEngaged == true {
                    guard commander == player.key else { continue }
                    owner.parkBehavior(of: actor.key)
                    owner.targets.removeValue(forKey: actor.key)
                }
                // A spell's ally is a summon, so the summon distances narrow the leash.
                let distance = min(
                    owner.combatAI.followDistance(leaderIsPlayer: commander == player.key),
                    owner.combatAI.summonFollowFar
                )
                follow(actor, to: home, within: distance, world: world)
            }
        }

        /// A walk is asked for again only when the commander has moved on from its end.
        func follow(
            _ actor: CombatActorObservation, to home: SIMD3<Float>, within distance: Float,
            world: any CombatLoopWorld
        ) {
            guard
                let point = CombatAllyRule.followPoint(
                    ally: actor.feet, commander: home, followDistance: distance,
                    keep: owner.combatAI.summonFollowNear
                )
            else {
                if owner.following.removeValue(forKey: actor.key) != nil {
                    world.stopCombatMovement(of: actor.key)
                }
                return
            }
            if
                let walking = owner.following[actor.key],
                simd_distance(walking, point) < CombatAllyRule.keepDistance
            {
                return
            }
            if world.moveCombatActor(actor.key, to: point) {
                owner.following[actor.key] = point
            }
        }
    }
}
