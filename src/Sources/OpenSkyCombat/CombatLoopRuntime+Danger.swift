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
    func dodges(_ actor: CombatActorObservation, world: any CombatLoopWorld) -> Bool {
        var watch = dangerWatches[actor.key] ?? CombatDangerWatch()
        defer { dangerWatches[actor.key] = watch }
        let step = Self.fixedStepSeconds
        if watch.dodgeSeconds > 0 {
            watch.dodgeSeconds -= step
            return watch.dodgeSeconds > 0
        }
        watch.untilSample -= step
        guard watch.untilSample <= 0 else { return false }
        let range = danger.sampleSeconds
        watch.untilSample = range.lowerBound
            + (range.upperBound - range.lowerBound) * Float(dangerRandom.percent()) / 100
        let threats = world.combatDangerThreats().filter {
            !sameSide($0.source, as: actor.key, world: world)
        }
        let health = world.combatHealth(of: actor.key)
        var fighter = DangerActor(
            feet: actor.feet, radius: actor.capsule.radius, health: health,
            speed: Self.dodgeSpeed
        )
        watch.score = DangerRule.score(threats, for: fighter, seconds: danger.anticipateTime)
        guard watch.score > 0 else { return false }
        let chance = danger.chance(style: world.combatStyle(of: actor.key)?.avoidThreatChance
            ?? CombatStyleTuning.neutral.avoidThreatChance)
        guard Float(dangerRandom.percent()) < chance * 100 else { return false }
        let coin = dangerRandom.percent() < 50
        fighter.isMoving = behaviors[actor.key]?.phase == .approaching
        let reaches: (SIMD3<Float>) -> Bool = { world.moveCombatActor(actor.key, to: $0) }
        let found = DangerRule.dodge(
            from: threats, for: fighter, settings: (danger, coin), reaches: reaches
        )
        guard let found else { return false }
        watch.dodge = found
        watch.dodgeSeconds = found.seconds
        watch.dodgeCount += 1
        return true
    }

    /// A threat from the actor itself or from its own side does not count.
    private func sameSide(
        _ source: ReferenceKey?, as actor: ReferenceKey, world: any CombatLoopWorld
    ) -> Bool {
        guard let source else { return false }
        if source == actor {
            return true
        }
        let player = world.combatPlayer.key
        let sourceWithPlayer = source == player || commanders[source] == player
        return sourceWithPlayer == (commanders[actor] == player)
    }
}
