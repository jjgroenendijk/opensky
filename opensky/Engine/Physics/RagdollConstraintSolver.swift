// The joint solver (issue #197, roadmap item 15.6): what holds a ragdoll's
// bones together once the 15.2 integrator has moved them apart.
//
// ## The choice, and what was rejected
//
// This is a **sequential-impulse** solver. Each joint is visited a fixed number
// of times per substep; each visit computes the constraint's current violation,
// solves for the impulse that removes the violation's *rate*, and applies it to
// both bodies at once. Whatever positional drift survives the velocity pass is
// then pushed out of the positions, not out of the velocities.
//
// The rejected alternative was **position-based dynamics** (XPBD): project the
// positions onto the constraint manifold directly and read the velocities back
// out of the projection. PBD is more forgiving of stiff joint chains at low
// iteration counts, which is a real advantage for an eighteen-bone ragdoll, and
// it was seriously considered. It lost on one point: the contact solver item
// 15.2 already shipped is sequential-impulse with position-level penetration
// recovery (`DynamicBodySolverContacts.swift`), and a ragdoll bone is in contact
// with the floor and jointed to its neighbour *in the same substep*. Running two
// different solver families over one body's velocities means each family
// undoes part of the other's work every iteration, and the joint that lost the
// argument is the one visited first. Matching the contact solver's family makes
// the two passes composable — they are the same fixed-point iteration over the
// same quantity — and keeps a single set of tuning constants for both.
//
// ## Stability
//
// Three rules keep repeated collapse bounded, which is the acceptance gate:
//
//  1. Every impulse is derived from an effective mass that is checked for a
//     usable magnitude before it divides anything, and every result is
//     finite-checked before it reaches a body. A degenerate joint contributes
//     nothing rather than a NaN.
//  2. Positional error is corrected at a rate below one, so a joint pulled apart
//     by a deep contact recovery converges over several substeps instead of
//     snapping and injecting the energy the snap represents.
//  3. A limit impulse is one-sided and accumulated: it may only ever push back
//     into the allowed range, never pull, so a bone resting against its own
//     limit cannot be driven through it and out the other side.
//
// Determinism follows from the same shape as the contact solver: joints are
// visited in list order, for a fixed iteration count, with no early exit that
// depends on anything but the joint's own numbers.
//
// Documented in docs/engine/ragdoll.md.

import simd

nonisolated enum RagdollConstraintSolver {
    /// Velocity iterations per substep over the whole joint set. Higher than
    /// the contact solver's four because a joint chain propagates a correction
    /// one link per iteration, and a humanoid ragdoll is six links from pelvis
    /// to hand.
    static let iterationCount = 8
    /// Passes the position and orientation corrections make over the joint list
    /// before anything is actually moved.
    ///
    /// More than one because a correction propagates exactly one link per pass:
    /// the first tells the pelvis to move toward the thigh, and only the second
    /// tells the calf that the thigh moved. With a single pass the real-data
    /// probe measured the vanilla humanoid's knees sitting seven engine units
    /// apart forever, because the chain never converged and so the joints never
    /// stopped pulling.
    ///
    /// The passes accumulate into one move per body and that move is applied —
    /// and clamped — once. Applying each pass in turn instead lets a substep
    /// spend the whole `maximumPositionCorrection` budget `positionIterationCount`
    /// times over, which is a teleport rather than a correction: the same probe
    /// measured a settled corpse crawling across the floor at better than a unit
    /// a second, driven by nothing but its own position corrections doing work
    /// against gravity.
    static let positionIterationCount = 4
    /// Fraction of a joint's remaining positional error removed per substep.
    /// Below one for the reason in the header.
    static let positionCorrectionRate: Float = 0.4
    /// Positional error left alone, in engine units. A joint solved to exactly
    /// zero chatters against the contact solver, which is pushing the same
    /// bodies for its own reasons.
    static let positionSlop: Float = 0.05
    /// Fraction of an angular limit's remaining violation rotated out of the
    /// poses per substep. Below one for the same reason the positional rate is:
    /// a snap is energy, and pacing the recovery is not.
    static let angularCorrectionRate: Float = 0.2
    /// Angular violation left alone, in radians. About a fifth of a degree.
    /// Vanilla authors a couple of the humanoid's own joints a few degrees
    /// outside their limits at the bind pose, so a solver that chased zero would
    /// never stop turning a corpse that is already lying still.
    static let angularSlop: Float = 0.004
    /// Ceiling on how far one substep may turn a body to recover a limit, in
    /// radians. The angular counterpart of `maximumPositionCorrection`.
    static let maximumLimitCorrection: Float = 0.15
    /// Ceiling on how far one substep may move a body to fix joint drift, in
    /// engine units. The same guard `maximumCorrectionDistance` gives contacts,
    /// for the same reason.
    static let maximumPositionCorrection: Float = 2

    /// Runs the whole joint set over `bodies` for one substep.
    ///
    /// - Returns: how many limit constraints were found violated on the final
    ///   iteration, which is the panel's convergence readout.
    @discardableResult
    static func solve(
        joints: [RagdollJointDefinition],
        bodies: inout [DynamicBody],
        dt: Float
    ) -> Int {
        guard !joints.isEmpty, dt > 0, dt.isFinite else { return 0 }
        var accumulated = [RagdollLimitImpulses](
            repeating: RagdollLimitImpulses(), count: joints.count
        )
        var violations = 0
        for iteration in 0 ..< iterationCount {
            violations = 0
            for (index, joint) in joints.enumerated() {
                guard joint.isResolvable(in: bodies) else { continue }
                applyFriction(joint, bodies: &bodies, dt: dt / Float(iterationCount))
                solvePoint(joint, bodies: &bodies)
                violations += solveLimits(
                    joint, accumulated: &accumulated[index], bodies: &bodies
                )
            }
            // Only the last pass's tally is reported; the earlier ones describe
            // a state the solver has already moved on from.
            if iteration < iterationCount - 1 {
                violations = 0
            }
        }
        correctLimits(joints: joints, bodies: &bodies)
        correctPositions(joints: joints, bodies: &bodies)
        return violations
    }

    /// The joint's own resistance to being moved: removes a fraction of the
    /// relative angular velocity of its two bones, at the rate the file's
    /// `maxFriction` names.
    ///
    /// This is the one thing that makes a corpse stop. A jointed chain solved
    /// by impulses alone has a limit cycle at its ends — the real-data probe
    /// measured a vanilla humanoid lying on a floor whose hands and head still
    /// carried thirty-odd engine units a second after thirty seconds, with the
    /// whole body crawling a unit a second across the floor as a result. It is
    /// also the physically honest answer: a real body's joints are not
    /// frictionless, and the format authors a friction value for every one of
    /// them precisely because Havok uses it.
    ///
    /// It cannot destabilize anything, whatever the unit turns out to be. The
    /// impulse only ever opposes the existing relative motion and is clamped to
    /// at most all of it, so friction takes energy out and never puts any in.
    private static func applyFriction(
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

    /// Holds the two pivots together (or, for a stiff spring, `length` apart) by
    /// cancelling the relative velocity of the two anchor points.
    ///
    /// The three-by-three effective mass is the standard one: the two inverse
    /// masses on the diagonal, minus each body's lever arm run through its own
    /// world inverse inertia. Inverting it directly rather than iterating three
    /// scalar rows is what makes one visit remove the whole relative motion
    /// instead of a third of it.
    private static func solvePoint(
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
    private static func solveLimits(
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

    /// One one-sided angular limit: cancels whatever relative spin is carrying
    /// the joint further past the limit, and nothing more.
    ///
    /// The sign convention is stated once and held everywhere:
    /// `RagdollJointLimitPass.axis` is the direction for which
    /// `dot(angularVelocityB - angularVelocityA, axis)` is the rate the
    /// violation grows at. So the impulse that shrinks it is negative along that
    /// axis, and the accumulated total is clamped at or below zero — a limit
    /// stops a bone leaving its range and never pulls one back toward it.
    ///
    /// **No restoring bias.** A first draft added one, driving the rate to a
    /// negative multiple of the error so a violated limit would recover through
    /// the velocities. That is the textbook Baumgarte term and it is exactly
    /// what `DynamicBodySolverContacts` already refuses to do with penetration,
    /// for the same reason: the velocity it writes is energy the constraint
    /// invented, and where the joint cannot actually reach its range the term
    /// fires every substep forever. The real-data probe measured it — a vanilla
    /// humanoid dropped on a floor climbed from twenty engine units a second to
    /// fifty-two over thirty seconds, with one ankle limit's violation growing
    /// from 0.27 to 1.77 radians as it was pumped. Recovery moved to
    /// `correctLimits`, which rotates the *poses*, and the divergence went away.
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

    /// Rotates the poses of every joint that is still outside its limits back
    /// toward them, after the velocity pass has done what it can.
    ///
    /// The angular counterpart of `correctPositions`, and accumulated per body
    /// for the same reason: a bone carrying three joints would otherwise be
    /// turned three times for the one misalignment it has. The share each body
    /// takes is its inverse inertia about the limit's own axis, so a heavy
    /// torso turns less than the arm hanging off it.
    private static func correctLimits(
        joints: [RagdollJointDefinition],
        bodies: inout [DynamicBody]
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
    private static func correctPositions(
        joints: [RagdollJointDefinition],
        bodies: inout [DynamicBody]
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
        body.linearVelocity += impulse * body.definition.inverseMass
        body.angularVelocity += body.worldInverseInertia
            * simd_cross(point - body.position, impulse)
        clampVelocities(of: &body)
    }

    private static func addAngularVelocity(
        _ impulse: SIMD3<Float>,
        to body: inout DynamicBody
    ) {
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
nonisolated struct RagdollLimitImpulses: Sendable {
    private var values = SIMD4<Float>()

    subscript(slot: Int) -> Float {
        get { slot >= 0 && slot < 4 ? values[slot] : 0 }
        set {
            guard slot >= 0, slot < 4 else { return }
            values[slot] = newValue
        }
    }
}
