// Fixed-step rigid-body solver on `PhysicsStep.fixedTimeStep` (1/120 s). Per step:
// gravity and damping, then substeps short enough to stop tunneling. Each substep
// integrates, solves contacts with sequential impulses, and pushes penetration out of
// positions (a velocity bias never lets a body sleep). Quiet bodies sleep. Fixed order
// and iteration counts make it bit-deterministic. See docs/engine/dynamic-bodies.md.

import OpenSkyFormatsCore
import simd

/// What one step needs from the world outside the body set.
nonisolated public struct DynamicStepWorld {
    /// Static broadphase, normally `CellSceneComposition.collisionCandidates`.
    public let staticCandidates: (ModelBounds) -> [StaticCollisionShape]
    /// Engine units per second squared, Z-up. Defaults to the same constant the
    /// player capsule falls under.
    public var gravity = SIMD3<Float>(0, 0, -PhysicsStep.gravity)

    public init(
        staticCandidates: @escaping (ModelBounds) -> [StaticCollisionShape] = { _ in [] },
        gravity: SIMD3<Float> = SIMD3(0, 0, -PhysicsStep.gravity)
    ) {
        self.staticCandidates = staticCandidates
        self.gravity = gravity
    }
}

/// What one step did, for the panel readout and the perf gate.
nonisolated public struct DynamicStepStats: Equatable, Sendable {
    public var activeBodyCount = 0
    public var sleepingBodyCount = 0
    public var contactCount = 0
    /// Contacts between two dynamic bodies. On a ragdoll that is bone against bone,
    /// filtered by self-collision.
    public var pairContactCount = 0
    public var substepCount = 0
    /// Bodies whose integrated pose came back non-finite and were reset. Always
    /// zero on well-formed input; a non-zero value is a bug, not a tolerance.
    public var recoveredBodyCount = 0
    /// Joint limits still violated after the last iteration of the last substep. Zero
    /// means converged; the panel shows it and the stability gate bounds it.
    public var jointViolationCount = 0
}

nonisolated public enum DynamicBodySolver: Sendable {
    /// Solver iterations per substep. Four is enough for a stack of a handful of
    /// clutter items to settle without visible sink at 120 Hz.
    public static let iterationCount = 4
    /// Ceiling on substeps per step, so an absurd velocity costs bounded time.
    /// Motion beyond what these substeps cover is discarded — see the header.
    public static let maximumSubstepCount = 8
    /// Penetration left unresolved, in engine units. Resolving to exactly zero
    /// makes resting contacts flicker in and out.
    public static let penetrationSlop: Float = 0.5
    /// Fraction of the remaining penetration pushed out of the positions per
    /// substep. Below one so a deep recovery is spread over several substeps
    /// rather than snapping.
    public static let correctionRate: Float = 0.4
    /// Ceiling on how far one substep may move a body to recover penetration,
    /// in engine units. Vanilla authors clutter *inside* the shelf it stands on,
    /// so a body's first contacts are routinely tens of units deep; without a
    /// ceiling the recovery reads as a launch and the body leaves the world.
    public static let maximumCorrectionDistance: Float = 1.5
    /// Below this closing speed a contact is treated as resting and gets no
    /// bounce, whatever the body's restitution. Engine units per second.
    public static let restitutionThreshold: Float = 120
    /// Sleep thresholds and the step count under them. The angular one is per body: the
    /// spin at which the collider's outer point moves at `sleepLinearSpeed`, because one
    /// constant suits neither a cup nor a table.
    public static let sleepLinearSpeed: Float = 6
    /// Ceiling on the derived angular threshold, so a body with an implausibly
    /// small collider is not allowed to sleep while visibly spinning.
    public static let maximumSleepAngularSpeed: Float = 0.7
    public static let sleepStepCount = 60

    /// The spin at which the farthest point of `body`'s collider moves at
    /// `sleepLinearSpeed`.
    public static func sleepAngularSpeed(of body: DynamicBody) -> Float {
        let radius = body.definition.boundingRadius
        guard radius > Float.ulpOfOne else { return maximumSleepAngularSpeed }
        return min(sleepLinearSpeed / radius, maximumSleepAngularSpeed)
    }

    /// Advances every body one fixed step. Non-empty `joints` means one ragdoll: the joint
    /// solver runs after contacts in each substep. Bones touch only where `selfCollision`
    /// allows, because overlapping vanilla capsules made corpses jitter. Default: none.
    @discardableResult
    public static func step(
        bodies: inout [DynamicBody],
        world: DynamicStepWorld,
        dt: Float,
        joints: [RagdollJointDefinition] = [],
        selfCollision: RagdollSelfCollision = .disabled
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
        let isRagdoll = !joints.isEmpty
        for _ in 0 ..< substeps {
            for index in bodies.indices where !bodies[index].isSleeping {
                integratePose(&bodies[index], dt: substepTime, stats: &stats)
            }
            let contacts = gatherContacts(
                bodies: bodies,
                world: world,
                selfCollision: isRagdoll ? selfCollision : nil
            )
            stats.contactCount = max(stats.contactCount, contacts.count)
            stats.pairContactCount = max(
                stats.pairContactCount, contacts.count(where: { $0.other != nil })
            )
            // A ragdoll whose every bone is asleep is not solved at all. Its
            // joints are as satisfied as they are going to get, nothing is
            // moving them, and running the pass anyway both costs a settled
            // corpse solver time forever and reports its sub-degree residual to
            // the panel as work still outstanding.
            if isRagdoll, bodies.contains(where: { !$0.isSleeping }) {
                stats.jointViolationCount = resolveRagdoll(
                    contacts: contacts,
                    joints: joints,
                    bodies: &bodies,
                    dt: substepTime
                )
            } else {
                resolve(contacts: contacts, bodies: &bodies)
            }
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
    public static func substepDistance(of body: DynamicBody) -> Float {
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

    /// `selfCollision` is nil for ordinary clutter, where every pair of bodies
    /// may touch, and the admitted set for a ragdoll, where most may not.
    private static func gatherContacts(
        bodies: [DynamicBody],
        world: DynamicStepWorld,
        selfCollision: RagdollSelfCollision? = nil
    ) -> [DynamicContact] {
        // Sampling a body's collider allocates, so each body is sampled at most once
        // per substep, and a sleeping body only when an awake one may touch it.
        let pairs = DynamicBodyBroadPhase.candidatePairs(bodies) { first, second in
            selfCollision?.admits(first, second) ?? true
        }
        var samples = [[(point: SIMD3<Float>, radius: Float)]?](repeating: nil, count: bodies.count)
        func sampled(_ index: Int) -> [(point: SIMD3<Float>, radius: Float)] {
            if let cached = samples[index] {
                return cached
            }
            let taken = bodies[index].contactSamples()
            samples[index] = taken
            return taken
        }
        var contacts: [DynamicContact] = []
        for index in bodies.indices where !bodies[index].isSleeping {
            let body = bodies[index]
            contacts += DynamicBodyContacts.staticContacts(
                body: body,
                index: index,
                samples: sampled(index),
                shapes: world.staticCandidates(body.worldBounds)
            )
        }
        for (first, second) in pairs {
            contacts += DynamicBodyContacts.pairContacts(
                first: DynamicBodySamples(
                    body: bodies[first],
                    index: first,
                    samples: sampled(first)
                ),
                second: DynamicBodySamples(
                    body: bodies[second],
                    index: second,
                    samples: sampled(second)
                )
            )
        }
        return contacts
    }

    // MARK: - Sleep

    /// A quiet step counts toward sleep and a busy step counts back down, instead of a
    /// reset. Resting bodies on triangle soup twitch, so a reset kept them awake forever
    /// and unsaved.
    private static func updateSleep(_ body: inout DynamicBody) {
        guard !body.isSleeping else { return }
        let atRest = simd_length(body.linearVelocity) <= sleepLinearSpeed
            && simd_length(body.angularVelocity) <= sleepAngularSpeed(of: body)
        guard atRest else {
            body.restingSteps = max(0, body.restingSteps - 1)
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
    public static func clamped(_ vector: SIMD3<Float>, to limit: Float) -> SIMD3<Float> {
        guard vector.isFiniteVector else { return .zero }
        let length = simd_length(vector)
        return length > limit && length > Float.ulpOfOne ? vector / length * limit : vector
    }
}

nonisolated extension SIMD4 where Scalar == Float {
    public var isFiniteVector4: Bool {
        x.isFinite && y.isFinite && z.isFinite && w.isFinite
    }
}
