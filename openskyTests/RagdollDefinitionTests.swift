// Building a ragdoll from decoded skeleton data (issue #197, item 15.6).
//
// The input is a `NIFCollisionModel` assembled in code rather than decoded from
// bytes: this suite is about the resolution step — bodies onto bones by name,
// joints onto body indices, pivots into centre-of-mass-local frames — and
// `NIFCollisionConstraintTests` already covers the decode that produces one.

@testable import opensky
import simd
import Testing

struct RagdollDefinitionTests {
    /// A two-bone skeleton: bones a spacing apart along x, each with a capsule
    /// body centred on its bone, joined by a ragdoll cone at the midpoint.
    private static let spacing: Float = 30

    @Test
    func resolvesBodiesOntoBonesByName() throws {
        let model = Self.model(boneNames: ["Root", "Limb"])
        let definition = try #require(RagdollDefinition(
            model: model,
            boneNames: ["Root", "Limb", "Unrelated"],
            bindMatrices: Self.bindMatrices(count: 3)
        ))
        #expect(definition.bones.map(\.boneName) == ["Root", "Limb"])
        #expect(definition.bones.map(\.boneIndex) == [0, 1])
        #expect(definition.skipped.isEmpty)
    }

    /// A body whose target node names no bone of the animation skeleton is
    /// dropped and reported, rather than silently attached to bone zero.
    @Test
    func reportsAnUnresolvedBoneName() throws {
        let model = Self.model(boneNames: ["Root", "NotOnThisSkeleton"])
        let definition = try #require(RagdollDefinition(
            model: model,
            boneNames: ["Root"],
            bindMatrices: Self.bindMatrices(count: 1)
        ))
        #expect(definition.bones.map(\.boneName) == ["Root"])
        // The joint bound the dropped body, so it goes too — and says so
        // separately, rather than the bone's loss standing in for both.
        #expect(definition.skipped == [
            .unresolvedBoneName("NotOnThisSkeleton"),
            .unresolvedJointEnd(block: 100 * 1000 + 101)
        ])
        #expect(definition.joints.isEmpty)
    }

    /// A skeleton with no resolvable body at all produces no definition, rather
    /// than an empty one a caller would have to test for.
    @Test
    func refusesASkeletonWithNoResolvableBody() {
        let model = Self.model(boneNames: ["Missing"])
        #expect(RagdollDefinition(
            model: model, boneNames: ["Root"], bindMatrices: Self.bindMatrices(count: 1)
        ) == nil)
    }

    /// The joint's two anchors land in the same world place when the bodies are
    /// at their bind pose, which is the whole correctness statement for the
    /// pivot transform: a pivot authored in entity space has to arrive in the
    /// body's centre-of-mass-local frame or the joint starts out stretched.
    @Test
    func pivotsCoincideAtTheBindPose() throws {
        let definition = try #require(RagdollDefinition(
            model: Self.model(boneNames: ["Root", "Limb"]),
            boneNames: ["Root", "Limb"],
            bindMatrices: Self.bindMatrices(count: 2)
        ))
        let joint = try #require(definition.joints.first)
        let bodies = definition.bones.map { bone in
            DynamicBody(
                key: .generated(1),
                reference: FormID(1),
                cell: .interior(FormID(1)),
                definition: bone.body,
                originPosition: .zero,
                orientation: .identityRotation
            )
        }
        let anchors = joint.anchors(in: bodies)
        #expect(simd_distance(anchors.a, anchors.b) < 0.01)
    }

    /// The bind frame round-trips: a bone left at its bind pose comes back out
    /// of the write-back exactly where it started.
    @Test
    func theBindFrameRoundTrips() throws {
        let definition = try #require(RagdollDefinition(
            model: Self.model(boneNames: ["Root", "Limb"]),
            boneNames: ["Root", "Limb"],
            bindMatrices: Self.bindMatrices(count: 2)
        ))
        let bind = Self.bindMatrices(count: 2)
        let instance = try #require(RagdollInstance(
            definition: definition,
            animatedBoneMatrices: bind,
            actorToWorld: matrix_identity_float4x4,
            blendDuration: 0,
            cell: .interior(FormID(1)),
            actor: FormID(1),
            key: .generated(1)
        ))
        let written = instance.boneMatrices(worldToActor: matrix_identity_float4x4)
        for (index, bone) in definition.bones.enumerated() {
            let matrix = try #require(written[bone.boneName])
            #expect(
                simd_distance(matrix.columns.3.xyz, bind[index].columns.3.xyz) < 0.01,
                "\(bone.boneName) moved during a no-op hand-off"
            )
        }
    }

    // MARK: - Fixture

    /// Bind matrices for `count` bones spaced along x.
    private static func bindMatrices(count: Int) -> [float4x4] {
        (0 ..< count).map { MatrixMath.translation(SIMD3(Float($0) * spacing, 0, 0)) }
    }

    /// One collision body per named bone, plus a ragdoll cone joining each
    /// consecutive pair at the midpoint between them.
    ///
    /// The pivots are authored in each body's own entity space, exactly as a
    /// NIF authors them: the joint sits at `+spacing/2` from the first body and
    /// `-spacing/2` from the second.
    private static func model(boneNames: [String]) -> NIFCollisionModel {
        var bodies: [NIFCollisionBody] = []
        for (index, name) in boneNames.enumerated() {
            let block = 100 + index
            var constraints: [NIFCollisionConstraint] = []
            if index > 0 {
                constraints.append(cone(entityA: block - 1, entityB: block))
            }
            if index + 1 < boneNames.count {
                constraints.append(cone(entityA: block, entityB: block + 1))
            }
            bodies.append(body(name: name, block: block, index: index, constraints: constraints))
        }
        return NIFCollisionModel(
            bodies: bodies, unsupportedReachableBlocks: [:], decodeFailures: []
        )
    }

    private static func body(
        name: String,
        block: Int,
        index: Int,
        constraints: [NIFCollisionConstraint]
    ) -> NIFCollisionBody {
        let filter = NIFCollisionFilter(layer: 1, flags: 0, group: 0)
        return NIFCollisionBody(
            targetBlock: Int32(block),
            targetName: name,
            bodyBlock: block,
            carrier: .blendCollisionObject,
            collisionObjectFlags: 0,
            worldFilter: filter,
            rigidBodyFilter: filter,
            entityResponse: 1,
            rigidBodyResponse: 1,
            dynamics: dynamics,
            constraints: constraints,
            bodyFlags: 0,
            transform: MatrixMath.translation(SIMD3(Float(index) * spacing, 0, 0)),
            shapes: [NIFCollisionShape(
                transform: matrix_identity_float4x4,
                geometry: .sphere(radius: 6)
            )]
        )
    }

    private static var dynamics: NIFRigidBodyDynamics {
        NIFRigidBodyDynamics(
            mass: 8,
            inertiaTensor: matrix_identity_float3x3,
            centerOfMass: .zero,
            linearVelocity: .zero,
            angularVelocity: .zero,
            linearDamping: 0.1,
            angularDamping: 0.05,
            timeFactor: 1,
            gravityFactor: 1,
            friction: 0.5,
            rollingFrictionMultiplier: 0,
            restitution: 0.3,
            maxLinearVelocity: 100,
            maxAngularVelocity: 30,
            penetrationDepth: 0,
            rawMotionSystem: NIFMotionSystem.boxInertia.rawValue,
            rawDeactivatorType: 0,
            rawSolverDeactivation: 0,
            rawQualityType: 0
        )
    }

    private static func cone(entityA: Int, entityB: Int) -> NIFCollisionConstraint {
        NIFCollisionConstraint(
            block: entityA * 1000 + entityB,
            entityA: Int32(entityA),
            entityB: Int32(entityB),
            priority: 1,
            data: .ragdoll(NIFRagdollConstraint(
                frameA: frame(pivot: SIMD3(spacing / 2, 0, 0)),
                frameB: frame(pivot: SIMD3(-spacing / 2, 0, 0)),
                coneMaxAngle: 0.5,
                planeMinAngle: -0.4,
                planeMaxAngle: 0.4,
                twistMinAngle: -0.3,
                twistMaxAngle: 0.3,
                maxFriction: 10,
                motor: .none
            ))
        )
    }

    private static func frame(pivot: SIMD3<Float>) -> NIFConstraintRagdollFrame {
        NIFConstraintRagdollFrame(
            twist: SIMD3(1, 0, 0),
            plane: SIMD3(0, 0, 1),
            motor: SIMD3(0, 1, 0),
            pivot: pivot
        )
    }
}
