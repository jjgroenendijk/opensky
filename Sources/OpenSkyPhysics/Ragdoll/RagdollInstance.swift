// One live ragdoll. On hand-off each body starts at the animated pose with its
// velocity, then the skeleton blends to simulation over `m_durationToBlend`.
// The pose writes back into the same bone-name matrix dictionary that
// `SkinningPalette.posed(by:)` reads; unsimulated bones keep the animation.
// See docs/engine/ragdoll.md.

import OpenSkyBehavior
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import simd

/// How a ragdoll is currently driven.
nonisolated public enum RagdollPhase: Equatable, Sendable {
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

nonisolated public struct RagdollInstance: Sendable {
    public let definition: RagdollDefinition
    /// One body per `definition.bones` entry, index-aligned with it. Module-settable,
    /// because the solver owns these values during a step.
    public var bodies: [DynamicBody]
    /// Seconds the animated-to-simulated blend takes, from the controlling
    /// modifier's `m_durationToBlend`. Zero means an instant hand-off, which is
    /// what the `RagdollInstant` event asks for.
    public let blendDuration: Float
    /// Whether the bones may touch each other this step; the sidebar switch over the
    /// definition's pairs.
    public var isSelfCollisionEnabled = true
    /// The powered-ragdoll motor that holds the bones near the hand-off pose
    /// while the blend runs. Nil leaves the bones to the solver alone.
    public var motor: RagdollMotor?
    /// The hand-off pose of each body, index-aligned with `bodies`: the motor's target.
    public private(set) var motorTargets: [RagdollPose] = []
    public private(set) var blendElapsed: Float = 0
    public private(set) var lastStats = DynamicStepStats()
    /// Where the root bone was when the current settle window opened, and how
    /// long that window has been running.
    private var settleReference: SIMD3<Float>?
    private var settleElapsed: Float = 0
    /// Whether the one final joint projection has already been made for this
    /// spell of rest. Cleared by `wake()`, so a corpse that is hit and comes to
    /// rest again is projected again.
    private var hasProjectedAtRest = false

    public var phase: RagdollPhase {
        if bodies.allSatisfy(\.isSleeping) {
            return .settled
        }
        guard blendDuration > 0, blendElapsed < blendDuration else { return .simulated }
        return .blending(progress: blendElapsed / blendDuration)
    }

    /// How much of the pose the simulation owns right now, `0 ... 1`.
    public var simulationWeight: Float {
        guard blendDuration > 0 else { return 1 }
        return min(max(blendElapsed / blendDuration, 0), 1)
    }

    public var isSettled: Bool {
        bodies.allSatisfy(\.isSleeping)
    }

    /// Spawns a ragdoll from the pose the animation holds. `animatedBoneMatrices` are
    /// in actor space; `actorToWorld` places that space. Nil when the definition
    /// names no bone the pose supplies.
    public init?(
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
        var targets: [RagdollPose] = []
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
            targets.append(pose)
        }
        self.definition = definition
        self.bodies = bodies
        motorTargets = targets
        self.blendDuration = max(0, blendDuration.isFinite ? blendDuration : 0)
    }

    /// A ragdoll assembled from bodies directly, for the synthetic fixtures the
    /// deterministic tests build in code.
    public init(definition: RagdollDefinition, bodies: [DynamicBody], blendDuration: Float = 0) {
        self.definition = definition
        self.bodies = bodies
        self.blendDuration = max(0, blendDuration.isFinite ? blendDuration : 0)
    }

    // MARK: - Stepping

    /// How long the whole-ragdoll settling test watches, in seconds, and how far the
    /// root may travel in that time and still count as at rest. It checks
    /// displacement, so one marginal bone on uneven ground cannot delay rest.
    public static let settleWindow: Float = 1
    public static let settleDistance: Float = 3
    public static let settleJointSeparation: Float = 2
    public static let settleAngularViolation: Float = 0.06
    /// Pose-only projections made on arrival at rest. One pass closes only part of a
    /// joint's error. Measured on the vanilla left elbow, 32 passes close a 3.11-unit
    /// gap to 0.10 units; it runs once per rest, so the cost is negligible.
    public static let restProjectionCount = 32
    /// How far inside the settling thresholds the projection drives the joints
    /// before it stops. Half, so a corpse rests clear of the boundary rather
    /// than on it: the vanilla humanoid's worst joint stops at 0.024 radians
    /// against a 0.06 threshold instead of at 0.058.
    public static let restProjectionMargin: Float = 0.5

    /// Advances the ragdoll by one fixed step of the 15.2 clock.
    @discardableResult
    public mutating func step(world: DynamicStepWorld, dt: Float) -> DynamicStepStats {
        guard dt > 0, dt.isFinite else { return lastStats }
        blendElapsed = min(blendElapsed + dt, max(blendDuration, 0))
        applyMotor(dt: dt)
        lastStats = DynamicBodySolver.step(
            bodies: &bodies,
            world: world,
            dt: dt,
            joints: definition.joints,
            selfCollision: isSelfCollisionEnabled ? definition.selfCollision : .disabled
        )
        updateSettling(dt: dt)
        return lastStats
    }

    /// Pulls each body towards its hand-off pose, more weakly as the simulation
    /// takes over. After the blend the motor does nothing.
    private mutating func applyMotor(dt: Float) {
        guard let motor, motorTargets.count == bodies.count else { return }
        let weight = 1 - simulationWeight
        guard weight > 0 else { return }
        for index in bodies.indices where !bodies[index].isSleeping {
            let target = motorTargets[index]
            let body = bodies[index]
            let mass = body.definition.mass
            bodies[index].linearVelocity = motor.driven(
                body.linearVelocity, error: target.position - body.originPosition,
                mass: mass, dt: dt, weight: weight
            )
            bodies[index].angularVelocity = motor.driven(
                body.angularVelocity,
                error: RagdollMotor.angularError(from: body.orientation, to: target.orientation),
                mass: mass, dt: dt, weight: weight
            )
        }
    }

    /// Puts the whole ragdoll to sleep once its root stops travelling, and runs the
    /// final joint projection on either route to rest. Bones can also sleep one by
    /// one with a joint still stretched by a self-collision contact; projecting on
    /// arrival at rest closes it.
    private mutating func updateSettling(dt: Float) {
        guard !hasProjectedAtRest else { return }
        guard !isSettled else { return projectAtRest() }
        guard let root = bodies.first?.position else { return }
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
        guard constraintsAreSettled else { return }
        projectAtRest()
    }

    /// Sleeps every bone and projects the joints over the sleeping bodies, with no
    /// velocity. It repeats until every joint is inside `restProjectionMargin`, so a
    /// nearly satisfied pose still costs about one pass.
    private mutating func projectAtRest() {
        for index in bodies.indices {
            bodies[index].isSleeping = true
            bodies[index].linearVelocity = .zero
            bodies[index].angularVelocity = .zero
        }
        for _ in 0 ..< Self.restProjectionCount {
            RagdollConstraintSolver.correctPoses(
                joints: definition.joints, bodies: &bodies, includeSleeping: true
            )
            guard !constraintsAreWithin(Self.restProjectionMargin) else { break }
        }
        hasProjectedAtRest = true
    }

    /// Prevents the coordinated fallback from freezing a visibly unfinished
    /// joint merely because the root has stopped travelling.
    private var constraintsAreSettled: Bool {
        constraintsAreWithin(1)
    }

    /// Whether every joint is inside `fraction` of the settling thresholds.
    private func constraintsAreWithin(_ fraction: Float) -> Bool {
        definition.joints.allSatisfy { joint in
            let anchors = joint.anchors(in: bodies)
            guard
                simd_distance(anchors.a, anchors.b)
                < Self.settleJointSeparation * fraction
            else {
                return false
            }
            let frames = joint.worldFrames(in: bodies)
            return RagdollJointLimitPass.passes(of: joint, frames: frames).allSatisfy {
                $0.error < Self.settleAngularViolation * fraction
            }
        }
    }

    /// Wakes every bone, which is what a dev trigger and a fresh impact both do.
    public mutating func wake() {
        for index in bodies.indices {
            bodies[index].wake()
        }
        settleReference = nil
        settleElapsed = 0
        hasProjectedAtRest = false
    }

    // MARK: - Pose

    /// The simulated pose as actor-space bone matrices by name, for
    /// `SkinningPalette.posed(by:)`. `worldToActor` comes from the caller, because a
    /// re-streamed actor re-derives its placement.
    public func boneMatrices(worldToActor: float4x4) -> [String: float4x4] {
        var matrices: [String: float4x4] = [:]
        for (index, bone) in definition.bones.enumerated() where bodies.indices.contains(index) {
            let placement = worldToActor * bodies[index].worldMatrix
            matrices[bone.boneName] = placement
                * MatrixMath.translation(-bodies[index].definition.centerOfMass)
                * bone.bindBoneMatrix
        }
        return matrices
    }

    /// The pose to draw this frame: simulated bones mixed into animated ones at the
    /// blend weight. Matrix mixing is fine for a short blend; past it only the
    /// simulated pose remains.
    public func blendedBoneMatrices(
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
    public var restingRootPosition: SIMD3<Float>? {
        bodies.first?.originPosition
    }

    public var restingRootOrientation: simd_quatf? {
        bodies.first?.orientation
    }
}

/// A rigid pose pulled out of a matrix, and the mixing the blend needs.
nonisolated public struct RagdollPose: Sendable {
    public let position: SIMD3<Float>
    public let orientation: simd_quatf

    /// Nil for a matrix that carries no usable rigid part — a degenerate bind
    /// pose, or a non-finite animated one.
    public init?(matrix: float4x4) {
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
    public static func mix(_ lhs: float4x4, _ rhs: float4x4, weight: Float) -> float4x4 {
        let amount = min(max(weight, 0), 1)
        guard let first = RagdollPose(matrix: lhs), let second = RagdollPose(matrix: rhs) else {
            return amount >= 0.5 ? rhs : lhs
        }
        let translation = first.position + (second.position - first.position) * amount
        let rotation = BehaviorPoseMath.slerp(first.orientation, second.orientation, amount)
        return MatrixMath.translation(translation) * float4x4(rotation)
    }
}
