// The moves of a styled NPC beside its close-range loop: the surround and distant circle
// after a failed advance, and an archer's strafe. Each runs on its own clock, so a strafe
// keeps going through the draw. See docs/engine/combat-movement.md.

import Foundation
import OpenSkyCombatInterface
import simd

nonisolated struct CombatPathMoves: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case surround, distantCircle, strafe
    }

    struct Move: Equatable, Sendable {
        var kind: Kind
        var destination: SIMD3<Float>
        /// The other side, tried once when no path reaches the first.
        var alternate: SIMD3<Float>?
        var startedAt: Float
    }

    private(set) var move: Move?
    private(set) var clock: Float = 0
    /// When the advance's path first failed since it last reached its goal.
    private(set) var refusedSince: Float?
    /// The time of the next pass.
    private(set) var nextPass: Float = 0
    /// The choices left in this pass, tried after a refused path. Nil between passes.
    private(set) var pending: [Kind]?
    /// Moves started since construction, for the readout.
    private(set) var startedCount = 0

    mutating func tick(_ seconds: Float) {
        clock += seconds
    }

    /// The mover took or refused the advance's path.
    mutating func noteAdvance(reached: Bool) {
        refusedSince = reached ? nil : refusedSince ?? clock
    }

    func advanceFailed(after seconds: Float) -> Bool {
        refusedSince.map { clock - $0 > seconds } ?? false
    }

    var isPassDue: Bool {
        clock >= nextPass
    }

    /// Starts a pass over `choices`, unless one is under way.
    mutating func beginPass(_ choices: [Kind]) {
        pending = pending ?? choices
    }

    /// The next choice of the pass, or nil when none is left.
    mutating func nextChoice() -> Kind? {
        guard let first = pending?.first else { return nil }
        pending?.removeFirst()
        return first
    }

    /// Ends the pass with a wait. The advance then starts again.
    mutating func wait(_ seconds: Float) {
        pending = nil
        nextPass = clock + seconds
        refusedSince = nil
    }

    /// Starts a move to the first of `points`. Nil when there is none.
    mutating func start(_ kind: Kind, points: [SIMD3<Float>]) -> CombatMovementCommand? {
        guard let first = points.first else { return nil }
        move = Move(
            kind: kind,
            destination: first,
            alternate: points.dropFirst().first,
            startedAt: clock
        )
        startedCount += 1
        return .reposition(first)
    }

    /// One step of the move under way: it ends on arrival, or with a hold after
    /// `CombatCloseMoveLoop.timeoutSeconds`.
    mutating func check(actorPosition: SIMD3<Float>) -> CombatMovementCommand? {
        guard let running = move else { return nil }
        let offset = running.destination - actorPosition
        let arrived = simd_length(SIMD2(offset.x, offset.y)) <= CombatCloseMoveLoop.arrivalRadius
        let timedOut = clock - running.startedAt >= CombatCloseMoveLoop.timeoutSeconds
        guard arrived || timedOut else { return nil }
        move = nil
        pending = nil
        refusedSince = nil
        return timedOut ? .hold : nil
    }

    /// No path reaches the move's point. Its other side is tried once; else the move
    /// fails and the next step tries what is left of the pass.
    mutating func refused() -> SIMD3<Float>? {
        guard var running = move else { return nil }
        guard let alternate = running.alternate else {
            move = nil
            return nil
        }
        running.destination = alternate
        running.alternate = nil
        move = running
        return alternate
    }

    /// A strafe keeps going through the attack cycle; any other move ends with its phase.
    mutating func entering(_ phase: CombatBehaviorPhase) {
        refusedSince = nil
        let keepsStrafe = [.spacing, .windup, .contact, .recovery].contains(phase)
        if move?.kind != .strafe || !keepsStrafe {
            move = nil
            pending = nil
        }
    }
}

// MARK: - Points

nonisolated extension CombatPathMoves {
    /// The ring's middle on the line from the target to the actor, when the actor stands
    /// beyond or inside the ring. Nil inside the ring.
    static func surroundPoint(
        _ inputs: CombatBehaviorInputs, ring: ClosedRange<Float>
    ) -> SIMD3<Float>? {
        guard !ring.contains(inputs.distance) else { return nil }
        let middle = (ring.lowerBound + ring.upperBound) / 2
        return point(inputs, turnedBy: 0, radius: middle)
    }

    /// The actor's position turned about the target by the drawn angle, the side picked by
    /// `side` first.
    static func distantCirclePoints(
        _ inputs: CombatBehaviorInputs, settings: CombatMovementSettings,
        unit: Float, side: Bool
    ) -> [SIMD3<Float>] {
        var degrees = settings.distantCircleAngle.lerp(unit)
        if inputs.targetIsPlayer {
            degrees *= settings.playerAngleMult
        }
        let least = settings.minimumArcRadii * inputs.actorRadius / max(inputs.distance, 1)
        let angle = max(degrees * .pi / 180, least)
        let sides = side ? [angle, -angle] : [-angle, angle]
        return sides.map { point(inputs, turnedBy: $0, radius: inputs.distance) }
    }

    /// Sideways, at right angles to the line from the target to the actor.
    static func strafePoints(
        _ inputs: CombatBehaviorInputs, settings: CombatStrafeSettings,
        unit: Float, side: Bool
    ) -> [SIMD3<Float>] {
        let length = max(settings.distance.lerp(unit), settings.minimumRadii * inputs.actorRadius)
        let away = direction(inputs)
        let sideways = SIMD3(-away.y, away.x, 0) * length
        let sides = side ? [sideways, -sideways] : [-sideways, sideways]
        return sides.map { inputs.actorPosition + $0 }
    }

    /// The point `radius` from the target on the actor's bearing turned by `turn`, at the
    /// actor's height.
    static func point(
        _ inputs: CombatBehaviorInputs, turnedBy turn: Float, radius: Float
    ) -> SIMD3<Float> {
        let away = direction(inputs)
        let turned = SIMD2(
            away.x * cos(turn) - away.y * sin(turn), away.x * sin(turn) + away.y * cos(turn)
        ) * radius
        return SIMD3(
            inputs.targetPosition.x + turned.x, inputs.targetPosition.y + turned.y,
            inputs.actorPosition.z
        )
    }

    private static func direction(_ inputs: CombatBehaviorInputs) -> SIMD2<Float> {
        let offset = inputs.actorPosition - inputs.targetPosition
        let planar = SIMD2(offset.x, offset.y)
        return simd_length(planar) > 0 ? simd_normalize(planar) : SIMD2(1, 0)
    }
}
