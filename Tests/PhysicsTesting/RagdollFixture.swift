// Synthetic ragdolls for the solver suites. The chain is shaped like a leg:
// three bones, a cone at the hip and a limited hinge at the knee, as the
// vanilla census shows for `NPC L Thigh` and `NPC L Calf`.

@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
import simd

public enum RagdollFixture {
    /// Half the length of one bone, along its own local x.
    public static let boneHalfLength: Float = 12
    public static let boneRadius: Float = 4
    public static let boneMass: Float = 8

    /// One capsule bone lying along local x, centred at `center`.
    public static func bone(
        center: SIMD3<Float>,
        orientation: simd_quatf = .identityRotation,
        mass: Float = boneMass
    ) -> DynamicBody {
        let volume = DynamicCollisionVolume.radial(
            first: SIMD3(-boneHalfLength, 0, 0),
            second: SIMD3(boneHalfLength, 0, 0),
            radius: boneRadius
        )
        return DynamicBody(
            key: .generated(1),
            reference: FormID(0x200),
            cell: .interior(FormID(0x10)),
            definition: DynamicBodyDefinition(volumes: [volume], mass: mass),
            originPosition: center,
            orientation: orientation
        )
    }

    /// A joint at the far end of `bodyA` and the near end of `bodyB`. Primary
    /// axis is local x, the bone's long axis; secondary is local z, so cone and
    /// hinge directions are well defined.
    public static func joint(
        bodyA: Int,
        bodyB: Int,
        limits: RagdollJointLimits
    ) -> RagdollJointDefinition {
        RagdollJointDefinition(
            bodyA: bodyA,
            bodyB: bodyB,
            frameA: RagdollJointFrame(
                pivot: SIMD3(boneHalfLength, 0, 0),
                primaryAxis: SIMD3(1, 0, 0),
                secondaryAxis: SIMD3(0, 0, 1)
            ),
            frameB: RagdollJointFrame(
                pivot: SIMD3(-boneHalfLength, 0, 0),
                primaryAxis: SIMD3(1, 0, 0),
                secondaryAxis: SIMD3(0, 0, 1)
            ),
            limits: limits
        )
    }

    /// A definition with no skeleton mapping, for physics-only suites. `parts`
    /// are biped part numbers aligned with the bones; nil admits no
    /// self-collision pair.
    public static func definition(
        boneCount: Int,
        joints: [RagdollJointDefinition],
        parts: [UInt8?] = []
    ) -> RagdollDefinition {
        let volume = DynamicCollisionVolume.radial(
            first: SIMD3(-boneHalfLength, 0, 0),
            second: SIMD3(boneHalfLength, 0, 0),
            radius: boneRadius
        )
        let bones = (0 ..< boneCount).map { index in
            RagdollBoneDefinition(
                boneName: "Bone\(index)",
                boneIndex: index,
                body: DynamicBodyDefinition(volumes: [volume], mass: boneMass),
                bindBoneMatrix: MatrixMath.translation(
                    SIMD3(Float(index) * boneHalfLength * 2, 0, 0)
                ),
                bipedPart: parts.indices.contains(index) ? parts[index] : nil
            )
        }
        return RagdollDefinition(bones: bones, joints: joints)
    }

    /// Three bones from `origin`, hip on a cone and knee on a hinge.
    /// `hipLimits` overrides the cone to show the limit holds the chain. `kick`
    /// throws neighbours in opposite z directions, so both joints hit their
    /// limits; a straight drop would pass without any limit.
    public static func limb(
        origin: SIMD3<Float> = SIMD3(0, 0, 100),
        coneMaxAngle: Float = .pi / 6,
        hingeRange: (min: Float, max: Float) = (-.pi / 2, 0),
        hipLimits: RagdollJointLimits? = nil,
        kick: Float = 500
    ) -> RagdollInstance {
        let spacing = boneHalfLength * 2
        let bodies = (0 ..< 3).map { index -> DynamicBody in
            var body = bone(center: origin + SIMD3(Float(index) * spacing, 0, 0))
            body.linearVelocity = SIMD3(0, 0, index % 2 == 0 ? kick : -kick)
            return body
        }
        let joints = [
            joint(
                bodyA: 0,
                bodyB: 1,
                limits: hipLimits ?? .cone(
                    coneMaxAngle: coneMaxAngle,
                    planeMinAngle: -coneMaxAngle,
                    planeMaxAngle: coneMaxAngle,
                    twistMinAngle: -.pi / 8,
                    twistMaxAngle: .pi / 8
                )
            ),
            joint(
                bodyA: 1,
                bodyB: 2,
                limits: .limitedHinge(minAngle: hingeRange.min, maxAngle: hingeRange.max)
            )
        ]
        return RagdollInstance(
            definition: definition(boneCount: 3, joints: joints),
            bodies: bodies
        )
    }

    /// Two bones on a plain point constraint, the simplest thing that can come
    /// apart.
    public static func pair(origin: SIMD3<Float> = SIMD3(0, 0, 100)) -> RagdollInstance {
        let bodies = [
            bone(center: origin),
            bone(center: origin + SIMD3(boneHalfLength * 2, 0, 0))
        ]
        let joints = [joint(bodyA: 0, bodyB: 1, limits: .point)]
        return RagdollInstance(
            definition: definition(boneCount: 2, joints: joints),
            bodies: bodies
        )
    }

    /// A world with nothing but gravity, for the free-fall cases.
    public static var emptyWorld: DynamicStepWorld {
        DynamicStepWorld()
    }

    /// A world with a floor at `z`.
    public static func floorWorld(z: Float = 0) -> DynamicStepWorld {
        DynamicStepWorld(
            staticCandidates: DynamicBodyScene.query([DynamicBodyScene.floor(z: z)])
        )
    }

    /// Advances a ragdoll by `steps` fixed steps.
    public static func run(_ instance: inout RagdollInstance, world: DynamicStepWorld, steps: Int) {
        for _ in 0 ..< steps {
            instance.step(world: world, dt: PhysicsStep.fixedTimeStep)
        }
    }

    // MARK: - Measurements

    /// How far apart a joint's two anchors are, which is the point
    /// constraint's whole error.
    public static func separation(
        of joint: RagdollJointDefinition,
        in instance: RagdollInstance
    ) -> Float {
        let anchors = joint.anchors(in: instance.bodies)
        return simd_distance(anchors.a, anchors.b)
    }

    /// The angle between a joint's two primary axes, which is what a cone
    /// bounds.
    public static func coneAngle(
        of joint: RagdollJointDefinition,
        in instance: RagdollInstance
    ) -> Float {
        let frames = joint.worldFrames(in: instance.bodies)
        return RagdollMath.angle(between: frames.a.primaryAxis, and: frames.b.primaryAxis)
    }

    /// Kinetic plus gravitational potential energy of every bone, in engine
    /// units. The quantity the stability gate watches: it may fall, because
    /// damping and friction take energy out, but it must never climb.
    public static func energy(of instance: RagdollInstance, floor: Float = 0) -> Float {
        instance.bodies.reduce(0) { total, body in
            let mass = body.definition.mass
            let linear = 0.5 * mass * simd_length_squared(body.linearVelocity)
            let angular = 0.5 * mass * simd_length_squared(body.angularVelocity)
            let potential = mass * PhysicsStep.gravity * (body.position.z - floor)
            return total + linear + angular + potential
        }
    }

    /// Whether every bone's pose and motion is finite. The NaN gate.
    public static func isFinite(_ instance: RagdollInstance) -> Bool {
        instance.bodies.allSatisfy {
            $0.position.isFiniteVector
                && $0.orientation.vector.isFiniteVector4
                && $0.linearVelocity.isFiniteVector
                && $0.angularVelocity.isFiniteVector
        }
    }

    /// Every bone's pose as plain numbers, for the two-runs-match assertion.
    public static func trace(_ instance: RagdollInstance) -> [SIMD4<Float>] {
        instance.bodies.flatMap { [SIMD4($0.position, 0), $0.orientation.vector] }
    }
}
