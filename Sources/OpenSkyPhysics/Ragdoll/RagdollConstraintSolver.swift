// The ragdoll joint solver: sequential impulses, then position correction, matching
// the contact solver's family so both passes compose. Effective masses are checked
// and results finite-checked; position error corrects at a rate below one; limit
// impulses only push back. List order and fixed counts keep it deterministic.
// See docs/engine/ragdoll-solver.md.

import OpenSkyBehavior
import simd

nonisolated public enum RagdollConstraintSolver: Sendable {
    /// Velocity iterations per substep over the whole joint set. Higher than
    /// the contact solver's four because a joint chain propagates a correction
    /// one link per iteration, and a humanoid ragdoll is six links from pelvis
    /// to hand.
    public static let iterationCount = 16
    /// Position and orientation correction passes per substep. A correction moves one
    /// link per pass, so one pass never converges. Passes add into one move per body,
    /// applied and clamped once, so the budget is not spent several times.
    public static let positionIterationCount = 4
    /// Fraction of a joint's remaining positional error removed per substep.
    /// Below one for the reason in the header.
    public static let positionCorrectionRate: Float = 0.4
    /// Positional error left alone, in engine units. A joint solved to exactly
    /// zero chatters against the contact solver, which is pushing the same
    /// bodies for its own reasons.
    public static let positionSlop: Float = 0.05
    /// Fraction of an angular limit's remaining violation rotated out of the
    /// poses per substep. Below one for the same reason the positional rate is:
    /// a snap is energy, and pacing the recovery is not.
    public static let angularCorrectionRate: Float = 0.2
    /// Angular violation left alone, in radians. About a fifth of a degree.
    /// Vanilla authors a couple of the humanoid's own joints a few degrees
    /// outside their limits at the bind pose, so a solver that chased zero would
    /// never stop turning a corpse that is already lying still.
    public static let angularSlop: Float = 0.004
    /// Ceiling on how far one substep may turn a body to recover a limit, in
    /// radians. The angular counterpart of `maximumPositionCorrection`.
    public static let maximumLimitCorrection: Float = 0.15
    /// Ceiling on how far one substep may move a body to fix joint drift, in
    /// engine units. The same guard `maximumCorrectionDistance` gives contacts,
    /// for the same reason.
    public static let maximumPositionCorrection: Float = 2

    /// Runs the whole joint set over `bodies` for one substep.
    ///
    /// - Returns: how many limit constraints were found violated on the final
    ///   iteration, which is the panel's convergence readout.
    @discardableResult
    public static func solve(
        joints: [RagdollJointDefinition],
        bodies: inout [DynamicBody],
        dt: Float
    ) -> Int {
        guard !joints.isEmpty, dt > 0, dt.isFinite else { return 0 }
        var state = VelocityState(jointCount: joints.count)
        var violations = 0
        for _ in 0 ..< iterationCount {
            violations = solveVelocityIteration(
                joints: joints,
                bodies: &bodies,
                iterationTime: dt / Float(iterationCount),
                state: &state
            )
        }
        correctPoses(joints: joints, bodies: &bodies)
        return violations
    }

    /// Joint friction: removes part of the bones' relative spin at the `maxFriction`
    /// rate. It is what lets a corpse stop. It only opposes motion, clamped to all of
    /// it, so it can never add energy.
    public static func applyFriction(
        _ joint: RagdollJointDefinition,
        bodies: inout [DynamicBody],
        dt: Float
    ) {
        guard joint.maxFriction > 0, dt > 0 else { return }
        let relative = bodies[joint.bodyB].angularVelocity
            - bodies[joint.bodyA].angularVelocity
        guard let axis = RagdollMath.unit(relative) else { return }
        let inertia = bodies[joint.bodyA].worldInverseInertia
            + bodies[joint.bodyB].worldInverseInertia
        let effective = simd_dot(axis, inertia * axis)
        guard effective > Float.ulpOfOne, effective.isFinite else { return }
        let fraction = min(joint.maxFriction * dt, 1)
        let impulse = axis * (-simd_length(relative) * fraction / effective)
        guard impulse.isFiniteVector else { return }
        addAngularVelocity(-impulse, to: &bodies[joint.bodyA])
        addAngularVelocity(impulse, to: &bodies[joint.bodyB])
    }

    // MARK: - Point constraint

    /// Holds the two pivots together (or `length` apart) by cancelling the anchors'
    /// relative velocity. The 3x3 effective mass is inverted directly, so one visit
    /// removes all of it.
    public static func solvePoint(
        _ joint: RagdollJointDefinition,
        bodies: inout [DynamicBody]
    ) {
        let anchors = joint.anchors(in: bodies)
        var direction = anchors.b - anchors.a
        if case let .distance(length) = joint.limits {
            // A stiff spring constrains the distance only, so the correction is
            // along the line between the anchors and the free directions are
            // left to the solver's other passes.
            let separation = simd_length(direction)
            guard separation > Float.ulpOfOne else { return }
            direction = direction / separation * (separation - length)
        }
        let lever = (
            a: anchors.a - bodies[joint.bodyA].position,
            b: anchors.b - bodies[joint.bodyB].position
        )
        var relative = bodies[joint.bodyB].velocity(at: anchors.b)
            - bodies[joint.bodyA].velocity(at: anchors.a)
        if case .distance = joint.limits {
            let axis = simd_length(direction) > Float.ulpOfOne
                ? simd_normalize(direction) : SIMD3<Float>.zero
            relative = axis * simd_dot(relative, axis)
        }
        let effective = effectiveMass(
            bodies[joint.bodyA], bodies[joint.bodyB], leverA: lever.a, leverB: lever.b
        )
        guard let inverse = invert(effective) else { return }
        let impulse = inverse * -relative
        guard impulse.isFiniteVector else { return }
        addVelocity(-impulse, to: &bodies[joint.bodyA], at: anchors.a)
        addVelocity(impulse, to: &bodies[joint.bodyB], at: anchors.b)
    }

    /// The three-by-three effective mass of a point constraint between two
    /// bodies.
    private static func effectiveMass(
        _ first: DynamicBody,
        _ second: DynamicBody,
        leverA: SIMD3<Float>,
        leverB: SIMD3<Float>
    ) -> float3x3 {
        let scalar = first.definition.inverseMass + second.definition.inverseMass
        var matrix = float3x3(diagonal: SIMD3(repeating: scalar))
        let skewA = RagdollMath.skew(leverA)
        let skewB = RagdollMath.skew(leverB)
        matrix -= skewA * first.worldInverseInertia * skewA
        matrix -= skewB * second.worldInverseInertia * skewB
        return matrix
    }

    /// A matrix inverse that refuses a singular or non-finite one, because a
    /// joint between two bodies whose inertia has collapsed must contribute
    /// nothing rather than infinity.
    private static func invert(_ matrix: float3x3) -> float3x3? {
        let determinant = matrix.determinant
        guard determinant.isFinite, abs(determinant) > 1e-9 else { return nil }
        let inverse = matrix.inverse
        let columns = [inverse.columns.0, inverse.columns.1, inverse.columns.2]
        guard columns.allSatisfy(\.isFiniteVector) else { return nil }
        return inverse
    }

    // MARK: - Angular limits

    /// Solves whatever angular limits the joint carries.
    ///
    /// - Returns: how many of them were found violated.
    public static func solveLimits(
        _ joint: RagdollJointDefinition,
        accumulated: inout RagdollLimitImpulses,
        bodies: inout [DynamicBody]
    ) -> Int {
        let frames = joint.worldFrames(in: bodies)
        var violations = 0
        for (slot, limit) in RagdollJointLimitPass.passes(of: joint, frames: frames).enumerated()
            where limit.error > angularSlop
        {
            violations += 1
            apply(limit, accumulated: &accumulated[slot], joint: joint, bodies: &bodies)
        }
        return violations
    }

    /// One one-sided angular limit: cancels the spin carrying the joint past it. The
    /// accumulated impulse stays at or below zero along `RagdollJointLimitPass.axis`.
    /// No restoring bias: it pumped energy in; `correctLimits` rotates poses instead.
    private static func apply(
        _ limit: RagdollJointLimitPass,
        accumulated: inout Float,
        joint: RagdollJointDefinition,
        bodies: inout [DynamicBody]
    ) {
        let axis = limit.axis
        let inertia = bodies[joint.bodyA].worldInverseInertia
            + bodies[joint.bodyB].worldInverseInertia
        let effective = simd_dot(axis, inertia * axis)
        guard effective > Float.ulpOfOne, effective.isFinite else { return }
        let rate = simd_dot(
            bodies[joint.bodyB].angularVelocity - bodies[joint.bodyA].angularVelocity, axis
        )
        var impulse = -rate / effective
        let total = min(0, accumulated + impulse)
        impulse = total - accumulated
        accumulated = total
        let applied = axis * impulse
        guard applied.isFiniteVector else { return }
        addAngularVelocity(-applied, to: &bodies[joint.bodyA])
        addAngularVelocity(applied, to: &bodies[joint.bodyB])
    }

    /// Rotates still-violating joints' poses back toward their limits. Accumulated per
    /// body, shared by inverse inertia about the limit axis, so a torso turns less than an arm.
    public static func correctLimits(
        joints: [RagdollJointDefinition],
        bodies: inout [DynamicBody],
        includeSleeping: Bool = false
    ) {
        var turns = [SIMD3<Float>](repeating: .zero, count: bodies.count)
        for joint in joints where joint.isResolvable(in: bodies) {
            let frames = joint.worldFrames(in: bodies)
            for limit in RagdollJointLimitPass.passes(of: joint, frames: frames)
                where limit.error > angularSlop
            {
                let axis = limit.axis
                let first = simd_dot(axis, bodies[joint.bodyA].worldInverseInertia * axis)
                let second = simd_dot(axis, bodies[joint.bodyB].worldInverseInertia * axis)
                let total = first + second
                guard total > Float.ulpOfOne, total.isFinite else { continue }
                // The violation shrinks when B turns along -axis, so B takes a
                // negative share and A the opposite.
                let correction = (limit.error - angularSlop) * angularCorrectionRate
                turns[joint.bodyB] -= axis * (correction * second / total)
                turns[joint.bodyA] += axis * (correction * first / total)
            }
        }

        for index in bodies.indices {
            guard includeSleeping || !bodies[index].isSleeping else { continue }
            let turn = clampedTurn(turns[index])
            guard turn != .zero else { continue }
            let angle = simd_length(turn)
            let rotation = simd_quatf(angle: angle, axis: turn / angle)
            let updated = BehaviorPoseMath.normalized(rotation * bodies[index].orientation)
            guard updated.vector.isFiniteVector4 else { continue }
            bodies[index].orientation = updated
        }
    }

    /// A turn vector held to `maximumLimitCorrection`, refusing anything
    /// non-finite so a degenerate joint cannot spin a bone.
    private static func clampedTurn(_ turn: SIMD3<Float>) -> SIMD3<Float> {
        guard turn.isFiniteVector else { return .zero }
        let angle = simd_length(turn)
        guard angle > Float.ulpOfOne else { return .zero }
        return angle > maximumLimitCorrection
            ? turn / angle * maximumLimitCorrection : turn
    }

    // MARK: - Positional drift

    /// Pulls the two anchors of every joint back together in position, after the
    /// velocity pass has done what it can.
    ///
    /// Accumulated per body and applied once, exactly as the contact solver's
    /// recovery is: a bone with three joints on it would otherwise be moved
    /// three times for the one displacement it actually has.
    public static func correctPositions(
        joints: [RagdollJointDefinition],
        bodies: inout [DynamicBody],
        includeSleeping: Bool = false
    ) {
        var moves = [SIMD3<Float>](repeating: .zero, count: bodies.count)
        for _ in 0 ..< positionIterationCount {
            for joint in joints where joint.isResolvable(in: bodies) {
                let anchors = joint.anchors(in: bodies)
                var error = (anchors.b + moves[joint.bodyB]) - (anchors.a + moves[joint.bodyA])
                let distance = simd_length(error)
                guard distance.isFinite else { continue }
                if case let .distance(length) = joint.limits {
                    guard distance > Float.ulpOfOne else { continue }
                    error = error / distance * (distance - length)
                }
                guard simd_length(error) > positionSlop else { continue }
                let total = bodies[joint.bodyA].definition.inverseMass
                    + bodies[joint.bodyB].definition.inverseMass
                guard total > Float.ulpOfOne else { continue }
                let correction = error * positionCorrectionRate
                let share = bodies[joint.bodyA].definition.inverseMass / total
                moves[joint.bodyA] += correction * share
                moves[joint.bodyB] -= correction * (1 - share)
            }
        }
        for index in bodies.indices {
            guard includeSleeping || !bodies[index].isSleeping else { continue }
            let move = DynamicBodySolver.clamped(moves[index], to: maximumPositionCorrection)
            guard move != .zero, move.isFiniteVector else { continue }
            bodies[index].position += move
        }
    }

    // MARK: - Primitives

    /// The velocity half of `DynamicBody.applyImpulse` without the wake, for the
    /// same reason the contact solver has one: the solver is already inside a
    /// step and must not reset the resting tally of a bone that is settling.
    private static func addVelocity(
        _ impulse: SIMD3<Float>,
        to body: inout DynamicBody,
        at point: SIMD3<Float>
    ) {
        guard !body.isSleeping else { return }
        body.linearVelocity += impulse * body.definition.inverseMass
        body.angularVelocity += body.worldInverseInertia
            * simd_cross(point - body.position, impulse)
        clampVelocities(of: &body)
    }

    private static func addAngularVelocity(
        _ impulse: SIMD3<Float>,
        to body: inout DynamicBody
    ) {
        guard !body.isSleeping else { return }
        body.angularVelocity += body.worldInverseInertia * impulse
        clampVelocities(of: &body)
    }

    private static func clampVelocities(of body: inout DynamicBody) {
        body.linearVelocity = DynamicBodySolver.clamped(
            body.linearVelocity, to: body.definition.maximumLinearSpeed
        )
        body.angularVelocity = DynamicBodySolver.clamped(
            body.angularVelocity, to: body.definition.maximumAngularSpeed
        )
    }
}

/// The accumulated one-sided impulse of each limit a joint can carry. Four
/// slots because a ragdoll cone is the widest joint: cone, plane, twist, and one
/// spare the hinge family uses for its axis alignment.
nonisolated public struct RagdollLimitImpulses: Sendable {
    private var values = SIMD4<Float>()

    public subscript(slot: Int) -> Float {
        get { slot >= 0 && slot < 4 ? values[slot] : 0 }
        set {
            guard slot >= 0, slot < 4 else { return }
            values[slot] = newValue
        }
    }
}
