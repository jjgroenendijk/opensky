// A fighter looks at the threat list on a timer and sidesteps a danger that is too
// large. See docs/engine/danger-avoidance.md#dodging.

import Foundation
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

extension CombatLoopRuntime {
    /// The move speed a sidestep is timed with. OpenSky's value: the seam has no speed read.
    static let dodgeSpeed: Float = 370

    /// True while `actor` sidesteps a threat, so its machine does not steer it.
    /// A fighter that closes on `goal` is scored along that path, not where it stands.
    func dodges(
        _ actor: CombatActorObservation, goal: SIMD3<Float>, world: any CombatLoopWorld
    ) -> Bool {
        DangerDodges(owner: self).dodges(actor, goal: goal, world: world)
    }
}

extension CombatLoopRuntime {
    /// Decides when an actor dodges a danger.
    struct DangerDodges {
        let owner: CombatLoopRuntime

        func dodges(
            _ actor: CombatActorObservation, goal: SIMD3<Float>, world: any CombatLoopWorld
        ) -> Bool {
            var watch = owner.dangerWatches[actor.key] ?? CombatDangerWatch()
            defer { owner.dangerWatches[actor.key] = watch }
            let step = CombatLoopRuntime.fixedStepSeconds
            if watch.dodgeSeconds > 0 {
                watch.dodgeSeconds -= step
                return watch.dodgeSeconds > 0
            }
            watch.untilSample -= step
            guard watch.untilSample <= 0 else { return false }
            let range = owner.danger.sampleSeconds
            watch.untilSample = range.lowerBound
                + (range.upperBound - range.lowerBound) * Float(owner.dangerRandom.percent()) / 100
            let threats = world.combatDangerThreats().filter {
                !sameSide($0.source, as: actor.key, world: world)
            }
            let health = world.combatHealth(of: actor.key)
            var fighter = DangerActor(
                feet: actor.feet, radius: actor.capsule.radius, health: health,
                speed: CombatLoopRuntime.dodgeSpeed
            )
            if owner.behaviors[actor.key]?.phase == .approaching {
                fighter.isMoving = true
                fighter.goal = goal
            }
            watch.score = DangerRule.aheadScore(
                threats,
                for: fighter,
                seconds: owner.danger.anticipateTime
            )
            guard watch.score > 0 else { return false }
            let chance = owner.danger
                .chance(style: world.combatStyle(of: actor.key)?.avoidThreatChance
                    ?? CombatStyleTuning.neutral.avoidThreatChance)
            guard Float(owner.dangerRandom.percent()) < chance * 100 else { return false }
            let coin = owner.dangerRandom.percent() < 50
            let reaches: (SIMD3<Float>) -> Bool = { world.moveCombatActor(actor.key, to: $0) }
            let found = DangerRule.dodge(
                from: threats, for: fighter, settings: (owner.danger, coin), reaches: reaches
            )
            guard let found else { return false }
            watch.dodge = found
            watch.dodgeSeconds = found.seconds
            watch.dodgeCount += 1
            return true
        }

        /// A threat from the actor itself or from its own side does not count.
        func sameSide(
            _ source: ReferenceKey?, as actor: ReferenceKey, world: any CombatLoopWorld
        ) -> Bool {
            guard let source else { return false }
            if source == actor {
                return true
            }
            let player = world.combatPlayer.key
            let sourceWithPlayer = source == player || owner.commanders[source] == player
            return sourceWithPlayer == (owner.commanders[actor] == player)
        }
    }
}
