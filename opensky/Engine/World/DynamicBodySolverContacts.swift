// Contact resolution for the dynamic solver, split from DynamicBodySolver for
// the type-length limit (issue #193).
//
// Accumulated sequential impulses: each contact is visited a fixed number of
// times per substep, its normal impulse is kept non-negative across those
// visits, and friction is clamped against whatever normal impulse has
// accumulated so far. Leftover penetration is then pushed out of the positions
// rather than out of the velocities, which is what lets a resting body reach
// the sleep thresholds instead of standing on a permanent upward bias.
//
// Documented in docs/engine/dynamic-bodies.md.

import simd

nonisolated extension DynamicBodySolver {
    /// Internal rather than private because `step` lives in the other half of
    /// this enum; the split is for the type-length limit, not for encapsulation.
    static func resolve(
        contacts: [DynamicContact],
        bodies: inout [DynamicBody]
    ) {
        guard !contacts.isEmpty else { return }
        // A sleeping body touched by a *moving* one rejoins the simulation,
        // which is what makes a shoved crate knock over the one beside it.
        //
        // "Moving" rather than "awake" is load-bearing. A body that has come to
        // rest stays awake for `sleepStepCount` steps before it is allowed to
        // sleep, so waking on mere wakefulness makes a touching pair alternate
        // forever: one falls asleep, its still-awake neighbour wakes it a step
        // later, and neither ever stays down. The real-data probe measured
        // exactly that, a body sleeping on step 61 and woken on step 62, over
        // and over for the whole run.
        //
        // The test is the toucher's resting tally rather than its velocity here
        // and now. A step begins by adding gravity to every awake body, so at
        // the moment contacts are resolved *every* awake body is moving at a
        // twelfth of gravity whatever it is really doing — reading velocity
        // directly makes the whole scene look busy. The tally is the same
        // measurement taken at the end of the previous step, after contacts had
        // cancelled that gravity, which is the honest moment to take it.
        for contact in contacts {
            guard let other = contact.other, bodies[other].isSleeping else { continue }
            if bodies[contact.body].restingSteps == 0 {
                bodies[other].wake()
            }
        }
        var accumulated = [Float](repeating: 0, count: contacts.count)
        for _ in 0 ..< iterationCount {
            for (index, contact) in contacts.enumerated() {
                accumulated[index] = applyNormalImpulse(
                    contact,
                    accumulated: accumulated[index],
                    bodies: &bodies
                )
                applyFrictionImpulse(contact, normalImpulse: accumulated[index], bodies: &bodies)
            }
        }
        correctPositions(contacts: contacts, bodies: &bodies)
    }

    /// Pushes leftover penetration out of the positions, split between two
    /// dynamic bodies by inverse mass so the heavier of a pair moves less.
    ///
    /// The corrections are accumulated per body rather than applied one contact
    /// at a time, and each contact is measured against what its body has already
    /// been moved. A sample generates one contact *per placed shape it is inside
    /// and per triangle soup it is near*, so a hull corner resting in a shelf
    /// routinely produces a dozen contacts carrying the same normal and the same
    /// depth. Applying each of them in turn moved the body a dozen times the
    /// penetration it actually had: the real-data probe caught a crate leaving a
    /// shelf at six units a substep and a second one shot 118 units through the
    /// farmhouse floor in a single step, after which both fell out of the world.
    /// Subtracting the accumulated move makes redundant contacts converge on the
    /// one correction they describe instead of summing.
    ///
    /// `maximumCorrectionDistance` then bounds what one substep may recover, so
    /// clutter vanilla authored deep inside its shelf climbs out over several
    /// steps rather than being launched. Recovery is not lost, only paced.
    private static func correctPositions(
        contacts: [DynamicContact],
        bodies: inout [DynamicBody]
    ) {
        var moves = [SIMD3<Float>](repeating: .zero, count: bodies.count)
        for contact in contacts {
            var remaining = contact.depth - penetrationSlop
                - simd_dot(moves[contact.body], contact.normal)
            if let other = contact.other {
                remaining += simd_dot(moves[other], contact.normal)
            }
            guard remaining > 0 else { continue }
            let excess = remaining * correctionRate
            guard let other = contact.other else {
                moves[contact.body] += contact.normal * excess
                continue
            }
            let total = bodies[contact.body].definition.inverseMass
                + bodies[other].definition.inverseMass
            guard total > Float.ulpOfOne else { continue }
            let share = bodies[contact.body].definition.inverseMass / total
            moves[contact.body] += contact.normal * (excess * share)
            moves[other] -= contact.normal * (excess * (1 - share))
        }
        for index in bodies.indices where !bodies[index].isSleeping {
            let move = clamped(moves[index], to: maximumCorrectionDistance)
            guard move != .zero else { continue }
            bodies[index].position += move
        }
    }

    private static func applyNormalImpulse(
        _ contact: DynamicContact,
        accumulated: Float,
        bodies: inout [DynamicBody]
    ) -> Float {
        let normal = contact.normal
        let effective = effectiveMass(contact, normal: normal, bodies: bodies)
        guard effective > Float.ulpOfOne else { return accumulated }
        let closing = simd_dot(relativeVelocity(contact, bodies: bodies), normal)
        let bounce = closing < -restitutionThreshold ? -contact.restitution * closing : 0
        var impulse = (-closing + bounce) / effective
        let total = max(0, accumulated + impulse)
        impulse = total - accumulated
        apply(impulse: normal * impulse, contact: contact, bodies: &bodies)
        return total
    }

    private static func applyFrictionImpulse(
        _ contact: DynamicContact,
        normalImpulse: Float,
        bodies: inout [DynamicBody]
    ) {
        guard normalImpulse > 0 else { return }
        let velocity = relativeVelocity(contact, bodies: bodies)
        let tangential = velocity - contact.normal * simd_dot(velocity, contact.normal)
        let speed = simd_length(tangential)
        guard speed > Float.ulpOfOne else { return }
        let direction = tangential / speed
        let effective = effectiveMass(contact, normal: direction, bodies: bodies)
        guard effective > Float.ulpOfOne else { return }
        let limit = contact.friction * normalImpulse
        let impulse = min(speed / effective, limit)
        apply(impulse: direction * -impulse, contact: contact, bodies: &bodies)
    }

    private static func relativeVelocity(
        _ contact: DynamicContact,
        bodies: [DynamicBody]
    ) -> SIMD3<Float> {
        var velocity = bodies[contact.body].velocity(at: contact.point)
        if let other = contact.other {
            velocity -= bodies[other].velocity(at: contact.point)
        }
        return velocity
    }

    private static func effectiveMass(
        _ contact: DynamicContact,
        normal: SIMD3<Float>,
        bodies: [DynamicBody]
    ) -> Float {
        var total = bodies[contact.body].definition.inverseMass
        total += angularTerm(bodies[contact.body], point: contact.point, normal: normal)
        if let other = contact.other {
            total += bodies[other].definition.inverseMass
            total += angularTerm(bodies[other], point: contact.point, normal: normal)
        }
        return total
    }

    private static func angularTerm(
        _ body: DynamicBody,
        point: SIMD3<Float>,
        normal: SIMD3<Float>
    ) -> Float {
        let lever = point - body.position
        let rotated = body.worldInverseInertia * simd_cross(lever, normal)
        return simd_dot(simd_cross(rotated, lever), normal)
    }

    private static func apply(
        impulse: SIMD3<Float>,
        contact: DynamicContact,
        bodies: inout [DynamicBody]
    ) {
        guard impulse.isFiniteVector else { return }
        addVelocity(impulse, to: &bodies[contact.body], at: contact.point)
        if let other = contact.other {
            addVelocity(-impulse, to: &bodies[other], at: contact.point)
        }
    }

    /// The velocity half of `DynamicBody.applyImpulse`, without the wake: the
    /// solver is already inside a step and a contact resolution must not reset
    /// the resting counter of a body that is settling.
    private static func addVelocity(
        _ impulse: SIMD3<Float>,
        to body: inout DynamicBody,
        at point: SIMD3<Float>
    ) {
        // A sleeping body is not integrated, so velocity written into it is
        // never spent — it just sits there and is waiting the moment something
        // wakes the body for an unrelated reason. Anything that should actually
        // move a sleeping body wakes it first.
        guard !body.isSleeping else { return }
        body.linearVelocity += impulse * body.definition.inverseMass
        body.angularVelocity += body.worldInverseInertia
            * simd_cross(point - body.position, impulse)
        body.linearVelocity = clamped(
            body.linearVelocity, to: body.definition.maximumLinearSpeed
        )
        body.angularVelocity = clamped(
            body.angularVelocity, to: body.definition.maximumAngularSpeed
        )
    }
}
