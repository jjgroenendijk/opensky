// The machine's side of the flanking loop: it replaces the advance and the close moves of
// a melee NPC whose style has the flanking flag. See docs/engine/combat-movement.md#flanking.

import Foundation
import OpenSkyCombatInterface

nonisolated extension CombatBehaviorMachine {
    /// One step of the flanking loop. Nil for an NPC without the flag, or with a bow.
    mutating func advanceFlanking(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep? {
        guard let flank = settings.flank, inputs.archery == nil else { return nil }
        let rules = CombatFlankLoop.Rules(
            settings: flank, strikingDistance: inputs.strikingDistance(settings: settings),
            isAttacking: phase.isMeleeAttack, goal: placeGoal(inputs),
            approachPace: approachPace(inputs)
        )
        var step = unchanged()
        if let order = flankLoop.advance(inputs, rules: rules) {
            step.command = command(order.command)
            step.pace = order.pace
            step.booksPlace = order.booksPlace
        }
        return step
    }
}
