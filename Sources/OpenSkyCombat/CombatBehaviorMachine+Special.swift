// The combat machine's choices that read the game's settings: the walk inside the advance
// radius, the caster's back-off, a heal below the restore threshold, an aimed shout, and
// a flying actor's air and perch stages (docs/engine/combat-behavior.md#game-settings).

import Foundation
import OpenSkyCombatInterface
import OpenSkyConditions
import simd

nonisolated extension CombatBehaviorPhase {
    /// Closing in or waiting for the next attack: nothing is in flight.
    var isWaitingToAttack: Bool {
        self == .approaching || self == .spacing || self == .blocking
    }
}

nonisolated extension CombatBehaviorMachine {
    /// A step that closes on the target, walking once inside the walk radius.
    mutating func approach(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        var step = unchanged()
        step.command = command(.approach(inputs.targetPosition))
        step.walks = inputs.distance <= settings.walkRadius
        return step
    }

    /// A heal when hurt below the threshold, else a shout when one is ready and reaches.
    mutating func startSpecialCast(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep? {
        if let heal = inputs.healSpell(settings: settings) {
            return startCast(heal)
        }
        if shoutCooldown <= 0, let shout = inputs.shout(settings: settings) {
            return startCast(shout)
        }
        return nil
    }

    /// A caster too close to its target steps back to the back-off radius first, for at
    /// most `backOffSeconds` of the approach. Nil when it may cast now.
    mutating func backOff(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep? {
        guard inputs.distance < settings.backOffRadius, phaseSeconds < settings.backOffSeconds
        else { return nil }
        guard secondsSinceCommand >= settings.commandIntervalSeconds else { return unchanged() }
        var step = unchanged()
        step.command = command(.flee(inputs.retreatPoint(to: settings.backOffRadius)))
        return step
    }

    /// A shout aims for at least the aim time and lets go once the actor faces the target.
    /// Facing away for twice the aim time drops it, and the actor waits the retry time.
    mutating func advanceShout(
        _ option: CombatSpellOption, inputs: CombatBehaviorInputs
    ) -> CombatBehaviorStep {
        guard phaseSeconds >= settings.shoutAimSeconds else { return unchanged() }
        let aimed = inputs.facingError.isFinite
            && abs(inputs.facingError) <= settings.shoutToleranceRadians
        guard aimed else {
            guard phaseSeconds >= settings.shoutAimSeconds * 2 else { return unchanged() }
            shoutCooldown = max(0, settings.shoutRetrySeconds)
            return enterSpacing()
        }
        pendingCast = nil
        shoutCooldown = max(0, option.cooldownSeconds)
        enter(.recovery)
        var step = unchanged()
        step.releasedCast = option
        return step
    }

    /// Moves a flying actor's stage clock while it fights.
    mutating func advanceFlight(seconds: Float, inputs: CombatBehaviorInputs) {
        guard inputs.flies, phase.isEngaged else { return }
        var generator = random
        _ = flight.advance(seconds: seconds, settings: settings.flight) {
            Float(generator.percent()) / 100
        }
        random = generator
    }

    /// In the air a flying actor circles at the orbit distance; on a perch it holds. Either
    /// way it heals, shouts, and casts from range, but does not swing.
    mutating func advanceAirborne(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        if phase == .blocking {
            enter(.spacing)
        }
        let ready = phase != .spacing || phaseSeconds >= settings.attackIntervalSeconds
        if ready, let special = startSpecialCast(inputs) {
            return special
        }
        if ready, let option = inputs.castableSpell(settings: settings) {
            return startCast(option)
        }
        guard secondsSinceCommand >= settings.commandIntervalSeconds else { return unchanged() }
        var step = unchanged()
        if flight.stage == .perch {
            step.command = command(.hold)
        } else {
            let point = inputs.orbitPoint(radius: settings.flight.orbitDistance, step: .pi / 6)
            step.command = command(.approach(point))
        }
        return step
    }
}
