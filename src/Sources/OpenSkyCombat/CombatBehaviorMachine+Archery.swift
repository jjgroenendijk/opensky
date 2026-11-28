// An NPC archer's turn in the gap between attacks: it steps back from a target too
// close, rolls its shot chance, and holds the full draw for its style's time.
// The rules live in `NPCArcheryRange`. See docs/engine/archery.md#npc-archers.

import Foundation
import OpenSkyCombatInterface
import OpenSkyConditions

nonisolated extension CombatBehaviorMachine {
    /// Nil when the actor holds no bow, so the melee spacing runs.
    mutating func advanceArcherSpacing(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep? {
        guard let range = inputs.archery else { return nil }
        if inputs.distance < range.backOffDistance {
            guard secondsSinceCommand >= settings.commandIntervalSeconds else { return unchanged() }
            var step = unchanged()
            step.command = command(.flee(inputs.retreatPoint(to: range.minimum)))
            return step
        }
        let strafe = strafeCommand(inputs)
        return merging(strafe, into: shot(inputs, range: range))
    }

    private mutating func shot(
        _ inputs: CombatBehaviorInputs, range: NPCArcheryRange
    ) -> CombatBehaviorStep {
        guard phaseSeconds >= settings.attackIntervalSeconds, inputs.weaponOut
        else { return unchanged() }
        let roll = Float(random.percent()) / 100
        guard roll < range.shotChance(secondsSinceShot: secondsSinceShot) else {
            return enterSpacing()
        }
        let unit = Float(random.percent()) / 100
        drawHold = range.hold(distance: inputs.distance, unit: unit)
        return startAttack()
    }

    /// The windup of a bow attack lasts the draw plus the hold at full draw.
    var windupSeconds: Float {
        settings.windupSeconds + drawHold
    }
}

nonisolated extension CombatBehaviorMachine {
    /// Drops a charge the world refused to start, without ending the fight:
    /// the actor lands in the gap between attacks and decides again from there.
    mutating func abandonCast() {
        guard phase == .casting else { return }
        pendingCast = nil
        enter(.spacing)
    }
}
