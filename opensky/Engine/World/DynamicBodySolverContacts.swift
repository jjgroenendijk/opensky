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
        // A sleeping body touched by a moving one rejoins the simulation, which
        // is what makes a shoved crate knock over the one beside it.
        for contact in contacts {
            guard let other = contact.other else { continue }
            if !bodies[contact.body].isSleeping, bodies[other].isSleeping {
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
    private static func correctPositions(
        contacts: [DynamicContact],
        bodies: inout [DynamicBody]
    ) {
        for contact in contacts {
            let excess = max(0, contact.depth - penetrationSlop) * correctionRate
            guard excess > 0 else { continue }
            guard let other = contact.other else {
                bodies[contact.body].position += contact.normal * excess
                continue
            }
            let total = bodies[contact.body].definition.inverseMass
                + bodies[other].definition.inverseMass
            guard total > Float.ulpOfOne else { continue }
            let share = bodies[contact.body].definition.inverseMass / total
            bodies[contact.body].position += contact.normal * (excess * share)
            bodies[other].position -= contact.normal * (excess * (1 - share))
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
