// One live ragdoll (issue #197, roadmap item 15.6): the bodies a definition
// spawned, the blend that carries the skeleton from animated to simulated, and
// the pose it writes back.
//
// ## The hand-off
//
// `hkbRigidBodyRagdollControlsModifier` is the graph's way of saying "the
// physics owns these bones now, over this many seconds". Its semantics, as this
// engine implements them:
//
//  1. Every bone body is placed at the pose the animation currently has it in,
//     by composing the animated bone matrix with the bind-pose frame the
//     definition carries. No body is teleported to a rest pose — a character
//     shot mid-stride falls from mid-stride.
//  2. Every bone body inherits the velocity that pose was arriving at, measured
//     from the previous animated pose over the frame's own delta, plus whatever
//     whole-actor velocity the caller hands over. A running character's corpse
//     keeps running for the moment it takes to fall.
//  3. The skeleton then blends from the animated pose to the simulated one over
//     `m_durationToBlend` seconds. Below that duration both poses are evaluated
//     and mixed; past it the animation is not consulted at all.
//
// ## Writing back
//
// The pose path this engine already has ends in `[String: float4x4]` — one
// skeleton-world matrix per bone name, handed to `SkinningPalette.posed(by:)`.
// A simulated bone writes into exactly that dictionary, so a ragdolled corpse
// reaches the skinning palette through the same call an idle animation does and
// the renderer needs to know nothing about physics. Bones the ragdoll does not
// simulate — fingers, the skirt chain, weapon nodes — keep whatever the
// animation left there, which is why a corpse still has hands.
//
// Documented in docs/engine/ragdoll.md.

import simd

/// How a ragdoll is currently driven.
nonisolated enum RagdollPhase: Equatable, Sendable {
    /// Bodies exist and are simulating, but the skeleton is still partly
    /// animated. The associated value is how far through the blend it is,
    /// `0 ... 1`.
    case blending(progress: Float)
    /// The simulation owns the skeleton outright.
    case simulated
    /// Simulating no longer: every body is asleep and the pose has stopped
    /// changing.
    case settled
}

nonisolated struct RagdollInstance: Sendable {
    let definition: RagdollDefinition
    /// One body per `definition.bones` entry, index-aligned with it.
    ///
    /// Settable within the module rather than `private(set)`, for the same
    /// reason `DynamicBodyWorld` hands its own array to the solver `inout`: the
    /// solver owns these values during a step, and the stability gate re-throws
    /// the same ragdoll sixty times through them. Nothing outside re-poses a
    /// ragdoll — the pose it has is the one the simulation gave it.
    var bodies: [DynamicBody]
    /// Seconds the animated-to-simulated blend takes, from the controlling
    /// modifier's `m_durationToBlend`. Zero means an instant hand-off, which is
    /// what the `RagdollInstant` event asks for.
    let blendDuration: Float
    private(set) var blendElapsed: Float = 0
    private(set) var lastStats = DynamicStepStats()
    /// Where the root bone was when the current settle window opened, and how
    /// long that window has been running.
    private var settleReference: SIMD3<Float>?
    private var settleElapsed: Float = 0

    var phase: RagdollPhase {
        if bodies.allSatisfy(\.isSleeping) {
            return .settled
        }
        guard blendDuration > 0, blendElapsed < blendDuration else { return .simulated }
        return .blending(progress: blendElapsed / blendDuration)
    }

    /// How much of the pose the simulation owns right now, `0 ... 1`.
    var simulationWeight: Float {
        guard blendDuration > 0 else { return 1 }
        return min(max(blendElapsed / blendDuration, 0), 1)
    }

    var isSettled: Bool {
        bodies.allSatisfy(\.isSleeping)
    }

    /// Spawns a ragdoll from the pose the animation currently holds.
    ///
    /// `animatedBoneMatrices` are skeleton-world matrices in the actor's own
    /// space; `actorToWorld` places that space in the world. Splitting them is
    /// what lets the same pose be used for the write-back, which has to go back
    /// through the actor's space to reach the skinning palette.
    ///
    /// Nil when the definition names no bone the pose supplies, which is the
    /// unresolvable case a caller should report rather than paper over.
    init?(
        definition: RagdollDefinition,
        animatedBoneMatrices: [float4x4],
        actorToWorld: float4x4,
        blendDuration: Float,
        cell: CellSceneLocation,
        actor: FormID,
        key: ReferenceKey,
        velocity: SIMD3<Float> = .zero
    ) {
        guard !definition.bones.isEmpty else { return nil }
        var bodies: [DynamicBody] = []
        bodies.reserveCapacity(definition.bones.count)
        for bone in definition.bones {
            guard animatedBoneMatrices.indices.contains(bone.boneIndex) else { return nil }
            let placement = actorToWorld
                * animatedBoneMatrices[bone.boneIndex]
                * bone.bindBoneInverse
            guard let pose = RagdollPose(matrix: placement) else { return nil }
            var body = DynamicBody(
                key: key,
                reference: actor,
                cell: cell,
                definition: bone.body,
                originPosition: pose.position,
                orientation: pose.orientation
            )
            body.linearVelocity = velocity
            bodies.append(body)
        }
        self.definition = definition
        self.bodies = bodies
        self.blendDuration = max(0, blendDuration.isFinite ? blendDuration : 0)
    }

    /// A ragdoll assembled from bodies directly, for the synthetic fixtures the
    /// deterministic tests build in code.
    init(definition: RagdollDefinition, bodies: [DynamicBody], blendDuration: Float = 0) {
        self.definition = definition
        self.bodies = bodies
        self.blendDuration = max(0, blendDuration.isFinite ? blendDuration : 0)
    }

    // MARK: - Stepping

    /// How long the whole-ragdoll settling test watches for, in seconds, and how
    /// far the root may travel in that time and still count as at rest.
    ///
    /// A ragdoll needs a settling test of its own because 15.2's per-body one
    /// never fires on a jointed chain. Measured on the vanilla humanoid: a
    /// corpse that has visibly stopped still carries thirty to fifty engine
    /// units a second in its hands and feet, far above `sleepLinearSpeed`, as
    /// the joint and contact solvers trade a small residual back and forth. The
    /// per-bone test therefore never lets the corpse sleep, and a corpse that
    /// never sleeps is also never persisted (issue #407 tracks shrinking that
    /// residual).
    ///
    /// So the question asked here is the one a viewer actually asks — has the
    /// body stopped *going* anywhere — and it is asked of displacement rather
    /// than velocity: the root travels less than `settleDistance` over
    /// `settleWindow`, and the whole ragdoll is put to sleep. An impulse wakes
    /// it again exactly as it wakes any 15.2 body.
    static let settleWindow: Float = 1
    static let settleDistance: Float = 3

    /// Advances the ragdoll by one fixed step of the 15.2 clock.
    @discardableResult
    mutating func step(world: DynamicStepWorld, dt: Float) -> DynamicStepStats {
        guard dt > 0, dt.isFinite else { return lastStats }
        blendElapsed = min(blendElapsed + dt, max(blendDuration, 0))
        lastStats = DynamicBodySolver.step(
            bodies: &bodies, world: world, dt: dt, joints: definition.joints
        )
        updateSettling(dt: dt)
        return lastStats
    }

    /// Puts the whole ragdoll to sleep once its root has stopped travelling.
    private mutating func updateSettling(dt: Float) {
        guard !isSettled, let root = bodies.first?.position else { return }
        guard let reference = settleReference else {
            settleReference = root
            settleElapsed = 0
            return
        }
        settleElapsed += dt
        guard settleElapsed >= Self.settleWindow else { return }
        settleElapsed = 0
        settleReference = root
        guard simd_distance(root, reference) < Self.settleDistance else { return }
        for index in bodies.indices {
            bodies[index].isSleeping = true
            bodies[index].linearVelocity = .zero
            bodies[index].angularVelocity = .zero
        }
    }

    /// Wakes every bone, which is what a dev trigger and a fresh impact both do.
    mutating func wake() {
        for index in bodies.indices {
            bodies[index].wake()
        }
        settleReference = nil
        settleElapsed = 0
    }

    /// Applies an impulse to the bone nearest `point`, waking the whole ragdoll
    /// so a settled corpse responds to being hit.
    mutating func applyImpulse(_ impulse: SIMD3<Float>, at point: SIMD3<Float>) {
        guard
            let nearest = bodies.indices.min(by: {
                simd_distance_squared(bodies[$0].position, point)
                    < simd_distance_squared(bodies[$1].position, point)
            })
        else { return }
        wake()
        bodies[nearest].applyImpulse(impulse, at: point)
    }

    // MARK: - Pose

    /// The simulated pose as skeleton-world matrices in the actor's own space,
    /// keyed by bone name — the shape `SkinningPalette.posed(by:)` consumes.
    ///
    /// `worldToActor` is the inverse of the placement the instance was spawned
    /// with. It is the caller's rather than the instance's because an actor that
    /// is streamed out and back re-derives its placement, and a cached inverse
    /// would quietly be the old one.
    func boneMatrices(worldToActor: float4x4) -> [String: float4x4] {
        var matrices: [String: float4x4] = [:]
        for (index, bone) in definition.bones.enumerated() where bodies.indices.contains(index) {
            let placement = worldToActor * bodies[index].worldMatrix
            matrices[bone.boneName] = placement
                * MatrixMath.translation(-bodies[index].definition.centerOfMass)
                * bone.bindBoneMatrix
        }
        return matrices
    }

    /// The pose to draw this frame: the simulated bones mixed into the animated
    /// ones at the blend's current weight.
    ///
    /// Matrix-level mixing rather than TRS-level, because both sides arrive as
    /// matrices here and a blend that only ever runs for half a second between
    /// two poses of the same rigid skeleton does not visibly shear. Past the
    /// blend the animated side is dropped entirely, so the corpse's steady state
    /// is exactly the simulated pose.
    func blendedBoneMatrices(
        animated: [String: float4x4],
        worldToActor: float4x4
    ) -> [String: float4x4] {
        let weight = simulationWeight
        let simulated = boneMatrices(worldToActor: worldToActor)
        guard weight < 1 else { return animated.merging(simulated) { _, new in new } }
        var blended = animated
        for (name, matrix) in simulated {
            guard let base = animated[name] else {
                blended[name] = matrix
                continue
            }
            blended[name] = RagdollPose.mix(base, matrix, weight: weight)
        }
        return blended
    }

    /// Where the actor's root sits now, for the resting transform persistence
    /// records. The first bone of a vanilla ragdoll is the pelvis, which is the
    /// closest thing a collapsed skeleton has to a root.
    var restingRootPosition: SIMD3<Float>? {
        bodies.first?.originPosition
    }

    var restingRootOrientation: simd_quatf? {
        bodies.first?.orientation
    }
}

/// A rigid pose pulled out of a matrix, and the mixing the blend needs.
nonisolated struct RagdollPose: Sendable {
    let position: SIMD3<Float>
    let orientation: simd_quatf

    /// Nil for a matrix that carries no usable rigid part — a degenerate bind
    /// pose, or a non-finite animated one.
    init?(matrix: float4x4) {
        let translation = matrix.columns.3
        guard translation.isFiniteVector4 else { return nil }
        let axes = [matrix.columns.0.xyz, matrix.columns.1.xyz, matrix.columns.2.xyz]
        guard
            let first = RagdollMath.unit(axes[0]),
            let second = RagdollMath.unit(axes[1]),
            let third = RagdollMath.unit(axes[2])
        else { return nil }
        let rotation = simd_quatf(float3x3(first, second, third))
        guard rotation.vector.isFiniteVector4 else { return nil }
        position = translation.xyz
        orientation = BehaviorPoseMath.normalized(rotation)
    }

    /// Linear mix of two placements: translation lerped, rotation slerped, and
    /// the scale of `lhs` kept because both sides describe the same rigid bone.
    static func mix(_ lhs: float4x4, _ rhs: float4x4, weight: Float) -> float4x4 {
        let amount = min(max(weight, 0), 1)
        guard let first = RagdollPose(matrix: lhs), let second = RagdollPose(matrix: rhs) else {
            return amount >= 0.5 ? rhs : lhs
        }
        let translation = first.position + (second.position - first.position) * amount
        let rotation = BehaviorPoseMath.slerp(first.orientation, second.orientation, amount)
        return MatrixMath.translation(translation) * float4x4(rotation)
    }
}
