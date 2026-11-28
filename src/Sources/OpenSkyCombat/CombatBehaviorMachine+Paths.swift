// The machine's side of the out-of-range, out-of-position, and strafe moves of a styled
// NPC. See docs/engine/combat-movement.md.

import Foundation
import OpenSkyCombatInterface
import OpenSkyConditions
import simd

nonisolated extension CombatBehaviorMachine {
    /// After the advance's path has failed for over a second: surround, then distant
    /// circle, then a wait. Nil lets the advance go on.
    mutating func advanceOutOfRange(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep? {
        guard let movement = settings.movement, inputs.archery == nil else { return nil }
        if paths.move != nil {
            var step = unchanged()
            if let issued = paths.check(actorPosition: inputs.actorPosition) {
                step.command = command(issued)
            }
            return step
        }
        guard paths.isPassDue else { return unchanged() }
        guard paths.advanceFailed(after: movement.advanceFailSeconds) else { return nil }
        paths.beginPass([.surround, .distantCircle])
        while let kind = paths.nextChoice() {
            let points = outOfRangePoints(kind, inputs: inputs, settings: movement)
            if let issued = paths.start(kind, points: points) {
                var step = unchanged()
                step.command = command(issued)
                step.pace = kind == .surround ? .run : .fastWalk
                return step
            }
        }
        paths.wait(movement.waitSeconds)
        return unchanged()
    }

    private mutating func outOfRangePoints(
        _ kind: CombatPathMoves.Kind, inputs: CombatBehaviorInputs,
        settings movement: CombatMovementSettings
    ) -> [SIMD3<Float>] {
        let inner = inputs.reach + settings.backOffRadius
        switch kind {
        case .surround:
            let ring = movement.surroundRing
            return CombatPathMoves.surroundPoint(
                inputs, ring: inner + ring.min ... inner + max(ring.min, ring.max)
            ).map { [$0] } ?? []
        case .distantCircle:
            guard
                CombatCloseMoveLoop.roll(movement.distantCircleChance, &random),
                abs(inputs.facingError) <= movement.startFacingDegrees * .pi / 180
            else { return [] }
            let unit = Float(random.percent()) / 100
            return CombatPathMoves.distantCirclePoints(
                inputs, settings: movement, unit: unit,
                side: CombatCloseMoveLoop.roll(0.5, &random)
            )
        case .strafe:
            return []
        }
    }

    /// An archer's strafe: a pass every quarter second rolls the strafe chance. Returns the
    /// command of a strafe that starts, or of one that ends with a hold.
    mutating func strafeCommand(
        _ inputs: CombatBehaviorInputs
    ) -> (command: CombatMovementCommand, pace: CombatPace?)? {
        guard let strafe = settings.strafe, inputs.archery != nil else { return nil }
        if paths.move != nil {
            return paths.check(actorPosition: inputs.actorPosition).map { ($0, nil) }
        }
        guard paths.isPassDue else { return nil }
        paths.wait(strafe.passSeconds)
        guard
            CombatCloseMoveLoop.roll(strafe.chance, &random),
            abs(inputs.facingError) <= strafe.startFacingDegrees * .pi / 180
        else { return nil }
        let points = CombatPathMoves.strafePoints(
            inputs, settings: strafe, unit: Float(random.percent()) / 100,
            side: CombatCloseMoveLoop.roll(0.5, &random)
        )
        return paths.start(.strafe, points: points).map { ($0, .fastWalk) }
    }

    /// `step` with the strafe's command. A strafe under way is not stopped by the hold
    /// that a missed shot roll gives.
    mutating func merging(
        _ strafe: (command: CombatMovementCommand, pace: CombatPace?)?,
        into step: CombatBehaviorStep
    ) -> CombatBehaviorStep {
        var step = step
        if let strafe, step.command == nil || step.command == .hold {
            step.command = command(strafe.command)
            step.pace = strafe.pace
        } else if paths.move?.kind == .strafe, step.command == .hold {
            step.command = nil
        }
        return step
    }

    /// An in-range NPC out of its place books the place where it stands, or walks to the
    /// nearest free one. Nil when it holds its place or none is free.
    mutating func reposition(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep? {
        guard
            let close = settings.closeRange, settings.movement != nil,
            let place = inputs.place, place.isOutOfPosition,
            !closeMoves.holdsPosition(now: phaseSeconds) else { return nil }
        var step = unchanged()
        if place.canBookHere {
            step.booksPlace = place.bearing
            return step
        }
        guard let goal = placeGoal(inputs) else { return nil }
        step.booksPlace = goal.bearing
        step.command = command(closeMoves.startReposition(
            to: goal.point, now: phaseSeconds, inputs: inputs, settings: close
        ))
        step.pace = approachPace(inputs)
        return step
    }

    /// The free place an advance or a reposition walks to: on the free bearing, just
    /// inside the striking distance.
    func placeGoal(_ inputs: CombatBehaviorInputs) -> (point: SIMD3<Float>, bearing: Float)? {
        guard
            settings.movement != nil, inputs.archery == nil,
            let bearing = inputs.place?.goalBearing else { return nil }
        let radius = max(0, inputs.strikingDistance(settings: settings) - Self.placeSlack)
        let point = SIMD3(
            inputs.targetPosition.x + cos(bearing) * radius,
            inputs.targetPosition.y + sin(bearing) * radius,
            inputs.targetPosition.z
        )
        return (point, bearing)
    }

    /// How far inside the striking distance a place lies, so the NPC arriving there is in
    /// reach. Ours.
    static let placeSlack: Float = 8

    /// The mover took or refused the advance's path.
    public mutating func noteAdvance(reached: Bool) {
        paths.noteAdvance(reached: reached)
        if !reached, flankLoop.move?.kind == .chase {
            flankLoop.refused()
        }
    }

    /// The path move under way, for the readout.
    public var pathMoveKind: String? {
        paths.move?.kind.rawValue
    }

    public var pathMoveCount: Int {
        paths.startedCount
    }
}
