// The machine's side of the close-range moves: the loop runs while spacing, and an
// attack or a phase change stops a move under way.
// See docs/formats/combat-style.md#close-range-movement.

import Foundation
import OpenSkyCombatInterface

nonisolated extension CombatBehaviorMachine {
    /// One step of the move loop, for a melee actor whose style sets close-range moves.
    mutating func advanceCloseMoves(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        var step = unchanged()
        guard let close = settings.closeRange, inputs.archery == nil else { return step }
        if let place = reposition(inputs) {
            return place
        }
        let rules = CombatCloseMoveLoop.Rules(
            settings: close, backOffDistance: inputs.reach + settings.backOffRadius
        )
        if let issued = closeMoves.advance(
            now: phaseSeconds, inputs: inputs, rules: rules, random: &random
        ) {
            step.command = command(issued)
            step.pace = issued == .hold ? nil : .walk
        }
        return step
    }

    /// `step` with a hold added when it left spacing while a move was under way.
    mutating func leaveCloseMoves(
        _ step: CombatBehaviorStep, wasMoving: Bool
    ) -> CombatBehaviorStep {
        var step = step
        if step.command == nil, wasMoving {
            step.command = command(.hold)
        }
        return step
    }

    /// No path reaches the point of the move just asked for. Returns the command for the
    /// circle's other side, when it has one.
    public mutating func refuseCloseMove() -> SIMD3<Float>? {
        if paths.move != nil {
            let other = paths.refused()
            if other != nil {
                secondsSinceCommand = 0
            }
            return other
        }
        guard case let .reposition(point)? = closeMoves.refused(now: phaseSeconds) else {
            return nil
        }
        secondsSinceCommand = 0
        return point
    }

    /// The close-range move under way, for the readout.
    public var closeMoveKind: String? {
        pathMoveKind ?? closeMoves.move?.kind.rawValue
    }

    /// Close-range moves started since construction.
    public var closeMoveCount: Int {
        closeMoves.startedCount + pathMoveCount
    }
}
