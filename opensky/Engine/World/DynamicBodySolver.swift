// Fixed-step integrator and contact solver for dynamic rigid bodies (issue
// #193, roadmap item 15.2).
//
// One `step` is one 1/120 tick of `WalkController.fixedTimeStep`, so the player
// capsule and the clutter around it advance on the same clock. Inside a step:
//
// 1. Gravity and damping go into the velocities, which are then clamped to the
//    body's own ceilings.
// 2. The step is split into substeps small enough that no body can move further
//    than `substepDistance(of:)` in one of them, and the leftover motion of an
//    implausibly fast body is dropped rather than integrated. That is the
//    tunneling guard: a body cannot cross a wall it never got a substep inside.
// 3. Each substep integrates the pose, gathers contacts, and resolves them with
//    accumulated sequential impulses, then pushes what penetration is left
//    out of the *positions* rather than out of the velocities. Correcting
//    through the velocities is the textbook Baumgarte term and it is what a
//    first draft of this solver did; it leaves a resting body with a standing
//    upward velocity that fights gravity forever, so the body never falls
//    under the sleep threshold. Moving the correction to position keeps the
//    recovery and lets a settled body actually stop.
// 4. A body that stays under both sleep thresholds long enough stops being
//    integrated at all.
//
// Determinism is a requirement, not a happy accident: bodies arrive already
// sorted by `ReferenceKey`, contacts are generated in body order, and the
// solver iterates them in list order for a fixed iteration count. Identical
// inputs therefore produce bit-identical trajectories.
//
// Documented in docs/engine/dynamic-bodies.md.

import simd

/// What one step needs from the world outside the body set.
nonisolated struct DynamicStepWorld {
    /// Static broadphase, normally `CellSceneComposition.collisionCandidates`.
    let staticCandidates: (ModelBounds) -> [StaticCollisionShape]
    /// Engine units per second squared, Z-up. Defaults to the same constant the
    /// player capsule falls under.
    var gravity = SIMD3<Float>(0, 0, -WalkController.gravity)

    init(
        staticCandidates: @escaping (ModelBounds) -> [StaticCollisionShape] = { _ in [] },
        gravity: SIMD3<Float> = SIMD3(0, 0, -WalkController.gravity)
    ) {
        self.staticCandidates = staticCandidates
        self.gravity = gravity
    }
}

/// What one step did, for the panel readout and the perf gate.
nonisolated struct DynamicStepStats: Equatable, Sendable {
    var activeBodyCount = 0
    var sleepingBodyCount = 0
    var contactCount = 0
    var substepCount = 0
    /// Bodies whose integrated pose came back non-finite and were reset. Always
    /// zero on well-formed input; a non-zero value is a bug, not a tolerance.
    var recoveredBodyCount = 0
}

nonisolated enum DynamicBodySolver {
    /// Solver iterations per substep. Four is enough for a stack of a handful of
    /// clutter items to settle without visible sink at 120 Hz.
    static let iterationCount = 4
    /// Ceiling on substeps per step, so an absurd velocity costs bounded time.
    /// Motion beyond what these substeps cover is discarded — see the header.
    static let maximumSubstepCount = 8
    /// Penetration left unresolved, in engine units. Resolving to exactly zero
    /// makes resting contacts flicker in and out.
    static let penetrationSlop: Float = 0.5
    /// Fraction of the remaining penetration pushed out of the positions per
    /// substep. Below one so a deep recovery is spread over several substeps
    /// rather than snapping.
    static let correctionRate: Float = 0.4
    /// Below this closing speed a contact is treated as resting and gets no
    /// bounce, whatever the body's restitution. Engine units per second.
    static let restitutionThreshold: Float = 120
    /// Sleep thresholds, and how many consecutive steps under them it takes.
    static let sleepLinearSpeed: Float = 6
    static let sleepAngularSpeed: Float = 0.12
    static let sleepStepCount = 60

    /// Advances every body by one fixed step.
    @discardableResult
    static func step(
        bodies: inout [DynamicBody],
        world: DynamicStepWorld,
        dt: Float
    ) -> DynamicStepStats {
        var stats = DynamicStepStats()
        guard dt > 0, dt.isFinite, !bodies.isEmpty else {
            stats.sleepingBodyCount = bodies.count(where: \.isSleeping)
            return stats
        }
        for index in bodies.indices where !bodies[index].isSleeping {
            integrateVelocity(&bodies[index], world: world, dt: dt)
        }
        let substeps = substepCount(bodies: bodies, dt: dt)
        stats.substepCount = substeps
        let substepTime = dt / Float(substeps)
        for _ in 0 ..< substeps {
            for index in bodies.indices where !bodies[index].isSleeping {
                integratePose(&bodies[index], dt: substepTime, stats: &stats)
            }
            let contacts = gatherContacts(bodies: bodies, world: world)
            stats.contactCount = max(stats.contactCount, contacts.count)
            resolve(contacts: contacts, bodies: &bodies)
        }
        for index in bodies.indices {
            updateSleep(&bodies[index])
        }
        stats.sleepingBodyCount = bodies.count(where: \.isSleeping)
        stats.activeBodyCount = bodies.count - stats.sleepingBodyCount
        return stats
    }

    // MARK: - Integration

    private static func integrateVelocity(
        _ body: inout DynamicBody,
        world: DynamicStepWorld,
        dt: Float
    ) {
        let definition = body.definition
        body.linearVelocity += world.gravity * definition.gravityFactor * dt
        body.linearVelocity *= max(0, 1 - definition.linearDamping * dt)
        body.angularVelocity *= max(0, 1 - definition.angularDamping * dt)
        body.linearVelocity = clamped(body.linearVelocity, to: definition.maximumLinearSpeed)
        body.angularVelocity = clamped(body.angularVelocity, to: definition.maximumAngularSpeed)
    }

    private static func integratePose(
        _ body: inout DynamicBody,
        dt: Float,
        stats: inout DynamicStepStats
    ) {
        let previousPosition = body.position
        let previousOrientation = body.orientation
        body.previousPosition = previousPosition
        body.position += body.linearVelocity * dt
        let spin = simd_quatf(
            real: 0,
            imag: body.angularVelocity * 0.5 * dt
        ) * body.orientation
        body.orientation = simd_quatf(
            vector: simd_normalize(body.orientation.vector + spin.vector)
        )
        guard body.position.isFiniteVector, body.orientation.vector.isFiniteVector4 else {
            body.position = previousPosition
            body.orientation = previousOrientation
            body.linearVelocity = .zero
            body.angularVelocity = .zero
            stats.recoveredBodyCount += 1
            return
        }
    }

    /// How far a body may move in one substep before a wall could be crossed
    /// without ever being sampled: half the collision margin plus a fraction of
    /// the body's own size, so a large crate substeps less often than a coin.
    static func substepDistance(of body: DynamicBody) -> Float {
        max(
            DynamicBodyContacts.contactMargin,
            body.definition.boundingRadius * 0.5
        )
    }

    private static func substepCount(bodies: [DynamicBody], dt: Float) -> Int {
        var required = 1
        for body in bodies where !body.isSleeping {
            let travel = simd_length(body.linearVelocity) * dt
            let allowed = substepDistance(of: body)
            guard allowed > 0, travel > allowed else { continue }
            required = max(required, Int((travel / allowed).rounded(.up)))
        }
        return min(max(required, 1), maximumSubstepCount)
    }

    // MARK: - Contacts

    private static func gatherContacts(
        bodies: [DynamicBody],
        world: DynamicStepWorld
    ) -> [DynamicContact] {
        // Sampling a body's collider allocates, and every body is asked for its
        // samples once against the static world and once per neighbour. Doing it
        // once per substep is the difference between an affordable step and an
        // unaffordable one in a room full of clutter.
        let samples = bodies.map { $0.contactSamples() }
        var contacts: [DynamicContact] = []
        for index in bodies.indices where !bodies[index].isSleeping {
            let body = bodies[index]
            contacts += DynamicBodyContacts.staticContacts(
                body: body,
                index: index,
                samples: samples[index],
                shapes: world.staticCandidates(body.worldBounds)
            )
        }
        for first in bodies.indices {
            for second in bodies.indices where second > first {
                guard !bodies[first].isSleeping || !bodies[second].isSleeping else { continue }
                // Bounding spheres reject a pair before any AABB is built, which
                // is most pairs in a scene where clutter is spread around a room.
                let reach = bodies[first].definition.boundingRadius
                    + bodies[second].definition.boundingRadius
                let separation = simd_distance_squared(
                    bodies[first].position, bodies[second].position
                )
                guard separation <= reach * reach else { continue }
                contacts += DynamicBodyContacts.pairContacts(
                    first: DynamicBodySamples(
                        body: bodies[first],
                        index: first,
                        samples: samples[first]
                    ),
                    second: DynamicBodySamples(
                        body: bodies[second],
                        index: second,
                        samples: samples[second]
                    )
                )
            }
        }
        return contacts
    }

    // MARK: - Sleep

    private static func updateSleep(_ body: inout DynamicBody) {
        guard !body.isSleeping else { return }
        let atRest = simd_length(body.linearVelocity) <= sleepLinearSpeed
            && simd_length(body.angularVelocity) <= sleepAngularSpeed
        guard atRest else {
            body.restingSteps = 0
            return
        }
        body.restingSteps += 1
        guard body.restingSteps >= sleepStepCount else { return }
        body.isSleeping = true
        body.linearVelocity = .zero
        body.angularVelocity = .zero
    }

    /// Internal for the same reason `resolve` is: the contact half of this enum
    /// clamps the velocities it writes.
    static func clamped(_ vector: SIMD3<Float>, to limit: Float) -> SIMD3<Float> {
        guard vector.isFiniteVector else { return .zero }
        let length = simd_length(vector)
        return length > limit && length > Float.ulpOfOne ? vector / length * limit : vector
    }
}

nonisolated extension SIMD4 where Scalar == Float {
    var isFiniteVector4: Bool {
        x.isFinite && y.isFinite && z.isFinite && w.isFinite
    }
}
