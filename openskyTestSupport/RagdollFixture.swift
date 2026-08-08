// Synthetic ragdolls for the constraint-solver suites (issue #197, item 15.6).
//
// Everything here is built in code: capsule bones, hand-authored joint frames,
// a floor described by four points. No game asset is read and none could be —
// the solver's inputs are engine values, not NIF bytes.
//
// The chain is deliberately the shape a limb is: three bones in a row, the first
// pair on a ragdoll cone and the second on a limited hinge, which is exactly the
// pattern the vanilla census reports for a leg (`NPC L Thigh` on a cone at the
// hip, `NPC L Calf -> NPC L Thigh` on a limited hinge at the knee).

@testable import opensky
import simd

enum RagdollFixture {
    /// Half the length of one bone, along its own local x.
    static let boneHalfLength: Float = 12
    static let boneRadius: Float = 4
    static let boneMass: Float = 8

    /// One capsule bone lying along local x, centred at `center`.
    static func bone(
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

    /// A joint at the far end of `bodyA` and the near end of `bodyB`, both bones
    /// lying along their own local x.
    ///
    /// The primary axis is local x — the bone's own long axis, which is what a
    /// twist is about — and the secondary is local z, so a cone's plane normal
    /// and a hinge's reference direction are both well defined and orthogonal to
    /// it.
    static func joint(
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

    /// A definition whose bones carry no skeleton mapping, for the solver suites
    /// that only exercise the physics.
    ///
    /// `parts` are the biped part numbers the bones' source filters would have
    /// carried, index-aligned with the bones. Nil throughout — the default —
    /// means no bone carries one, which admits no self-collision pair at all and
    /// is the behaviour every suite written before issue #413 assumes.
    static func definition(
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

    /// Three bones in a row starting at `origin`, hip on a cone and knee on a
    /// limited hinge.
    ///
    /// `hipLimits` overrides the cone, so a suite can run the identical chain
    /// with the limit removed and show that the limit is what held it.
    ///
    /// `kick` is what makes the chain interesting. A straight chain dropped flat
    /// onto a floor lands straight: every bone keeps the orientation it started
    /// with, no joint is ever asked to hold an angle, and a limit assertion over
    /// that run passes whether or not any limit is enforced. The kick throws
    /// neighbouring bones in opposite directions along z, so both joints are
    /// driven hard against their limits from the first step.
    static func limb(
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
    static func pair(origin: SIMD3<Float> = SIMD3(0, 0, 100)) -> RagdollInstance {
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
    static var emptyWorld: DynamicStepWorld {
        DynamicStepWorld()
    }

    /// A world with a floor at `z`.
    static func floorWorld(z: Float = 0) -> DynamicStepWorld {
        DynamicStepWorld(
            staticCandidates: DynamicBodyScene.query([DynamicBodyScene.floor(z: z)])
        )
    }

    /// Advances a ragdoll by `steps` fixed steps.
    static func run(_ instance: inout RagdollInstance, world: DynamicStepWorld, steps: Int) {
        for _ in 0 ..< steps {
            instance.step(world: world, dt: WalkController.fixedTimeStep)
        }
    }

    // MARK: - Measurements

    /// How far apart a joint's two anchors are, which is the point
    /// constraint's whole error.
    static func separation(
        of joint: RagdollJointDefinition,
        in instance: RagdollInstance
    ) -> Float {
        let anchors = joint.anchors(in: instance.bodies)
        return simd_distance(anchors.a, anchors.b)
    }

    /// The angle between a joint's two primary axes, which is what a cone
    /// bounds.
    static func coneAngle(
        of joint: RagdollJointDefinition,
        in instance: RagdollInstance
    ) -> Float {
        let frames = joint.worldFrames(in: instance.bodies)
        return RagdollMath.angle(between: frames.a.primaryAxis, and: frames.b.primaryAxis)
    }

    /// Kinetic plus gravitational potential energy of every bone, in engine
    /// units. The quantity the stability gate watches: it may fall, because
    /// damping and friction take energy out, but it must never climb.
    static func energy(of instance: RagdollInstance, floor: Float = 0) -> Float {
        instance.bodies.reduce(0) { total, body in
            let mass = body.definition.mass
            let linear = 0.5 * mass * simd_length_squared(body.linearVelocity)
            let angular = 0.5 * mass * simd_length_squared(body.angularVelocity)
            let potential = mass * WalkController.gravity * (body.position.z - floor)
            return total + linear + angular + potential
        }
    }

    /// Whether every bone's pose and motion is finite. The NaN gate.
    static func isFinite(_ instance: RagdollInstance) -> Bool {
        instance.bodies.allSatisfy {
            $0.position.isFiniteVector
                && $0.orientation.vector.isFiniteVector4
                && $0.linearVelocity.isFiniteVector
                && $0.angularVelocity.isFiniteVector
        }
    }

    /// Every bone's pose as plain numbers, for the two-runs-match assertion.
    static func trace(_ instance: RagdollInstance) -> [SIMD4<Float>] {
        instance.bodies.flatMap { [SIMD4($0.position, 0), $0.orientation.vector] }
    }
}
