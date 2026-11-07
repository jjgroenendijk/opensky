// Contact resolution for the dynamic solver: accumulated sequential impulses, normal
// impulse kept non-negative, friction accumulated and clamped to it. Each patch of
// contacts carries the weight first, then the points take what rotation is left. Penetration leaves
// through the
// positions, so a resting body can sleep. See docs/engine/dynamic-narrowphase.md.

import simd

nonisolated extension DynamicBodySolver {
    /// Internal rather than private because `step` lives in the other half of
    /// this enum; the split is for the type-length limit, not for encapsulation.
    public static func resolve(
        contacts: [DynamicContact],
        bodies: inout [DynamicBody]
    ) {
        guard !contacts.isEmpty else { return }
        wakeSleepingBodies(in: contacts, bodies: &bodies)
        var state = ContactSolveState(contacts: contacts, bodies: bodies)
        state.warmStart(bodies: &bodies)
        for _ in 0 ..< iterationCount {
            solveContactVelocityIteration(state: &state, bodies: &bodies)
        }
        state.storeWarmImpulses(in: &bodies)
        correctPositions(contacts: contacts, bodies: &bodies)
    }

    /// Solves a ragdoll's floor contacts and joints as one constraint set.
    /// Alternating their order avoids giving either family the last word on
    /// every iteration, while the shared accumulated impulses let both
    /// converge across the entire substep.
    public static func resolveRagdoll(
        contacts: [DynamicContact],
        joints: [RagdollJointDefinition],
        bodies: inout [DynamicBody],
        dt: Float
    ) -> Int {
        wakeSleepingBodies(in: contacts, bodies: &bodies)
        var contactState = ContactSolveState(contacts: contacts, bodies: bodies)
        var jointState = RagdollConstraintSolver.VelocityState(jointCount: joints.count)
        var violations = 0
        let iterationTime = dt / Float(RagdollConstraintSolver.iterationCount)
        for iteration in 0 ..< RagdollConstraintSolver.iterationCount {
            if iteration.isMultiple(of: 2) {
                solveContactVelocityIteration(state: &contactState, bodies: &bodies)
            }
            violations = RagdollConstraintSolver.solveVelocityIteration(
                joints: joints,
                bodies: &bodies,
                iterationTime: iterationTime,
                state: &jointState
            )
            if !iteration.isMultiple(of: 2) {
                solveContactVelocityIteration(state: &contactState, bodies: &bodies)
            }
        }
        RagdollConstraintSolver.correctPoses(joints: joints, bodies: &bodies)
        // Leave contacts satisfied at the substep boundary. Joint drift
        // recovery can otherwise push a bone back into the floor after contact
        // recovery has finished, manufacturing the next substep's impulse.
        correctPositions(contacts: contacts, bodies: &bodies)
        return violations
    }

    private static func wakeSleepingBodies(
        in contacts: [DynamicContact],
        bodies: inout [DynamicBody]
    ) {
        // A sleeping body touched by a moving one wakes. "Moving" uses the toucher's
        // resting tally from the last step, not "awake" (a pair would wake each other
        // forever) and not its velocity now (gravity was just added to every body).
        for contact in contacts {
            guard let other = contact.other, bodies[other].isSleeping else { continue }
            if bodies[contact.body].restingSteps == 0 {
                bodies[other].wake()
            }
        }
    }

    private static func solveContactVelocityIteration(
        state: inout ContactSolveState,
        bodies: inout [DynamicBody]
    ) {
        // Every other sweep runs backwards, so no corner of a box always goes first.
        let backward = !state.sweeps.isMultiple(of: 2)
        state.sweeps += 1
        solve(&state.patches, backward: backward, bodies: &bodies)
        solve(&state.points, backward: backward, bodies: &bodies)
    }

    private static func solve(
        _ set: inout ContactSet, backward: Bool, bodies: inout [DynamicBody]
    ) {
        let order = backward
            ? Array(set.contacts.indices.reversed()) : Array(set.contacts.indices)
        for index in order {
            let contact = set.contacts[index]
            set.normal[index] = applyNormalImpulse(
                contact, accumulated: set.normal[index], bodies: &bodies
            )
            set.friction[index] = applyFrictionImpulse(
                contact, normalImpulse: set.normal[index],
                accumulated: set.friction[index], bodies: &bodies
            )
        }
    }

    /// Pushes penetration out of positions, split by inverse mass. Moves add up per body
    /// and each contact subtracts what is done, so a dozen duplicate contacts give one
    /// move. `maximumCorrectionDistance` paces recovery over several substeps.
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

    /// The friction impulse so far, kept inside the cone the normal impulse allows,
    /// so four passes cannot add four times the limit.
    private static func applyFrictionImpulse(
        _ contact: DynamicContact,
        normalImpulse: Float,
        accumulated: SIMD3<Float>,
        bodies: inout [DynamicBody]
    ) -> SIMD3<Float> {
        let velocity = relativeVelocity(contact, bodies: bodies)
        let tangential = velocity - contact.normal * simd_dot(velocity, contact.normal)
        let speed = simd_length(tangential)
        var total = accumulated
        if speed > Float.ulpOfOne {
            let direction = tangential / speed
            let effective = effectiveMass(contact, normal: direction, bodies: bodies)
            if effective > Float.ulpOfOne {
                total -= direction * (speed / effective)
            }
        }
        let limit = contact.friction * max(normalImpulse, 0)
        let length = simd_length(total)
        if length > limit {
            total = length > Float.ulpOfOne ? total / length * limit : .zero
        }
        apply(impulse: total - accumulated, contact: contact, bodies: &bodies)
        return total
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

    static func apply(
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

/// Contacts and the impulses each has taken so far in this substep.
nonisolated struct ContactSet {
    let contacts: [DynamicContact]
    var normal: [Float]
    var friction: [SIMD3<Float>]

    init(_ contacts: [DynamicContact]) {
        self.contacts = contacts
        normal = [Float](repeating: 0, count: contacts.count)
        friction = [SIMD3<Float>](repeating: .zero, count: contacts.count)
    }
}

/// One substep's patches and points.
nonisolated struct ContactSolveState {
    var patches: ContactSet
    var points: ContactSet
    var sweeps = 0

    init(contacts: [DynamicContact], bodies: [DynamicBody]) {
        patches = ContactSet(DynamicContactPatch.supports(of: contacts, bodies: bodies))
        points = ContactSet(contacts)
    }
}
