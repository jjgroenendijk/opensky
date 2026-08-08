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
            .unresolvedJointEnd(block: RagdollSkeletonFixture.coneBlock(
                entityA: RagdollSkeletonFixture.block(of: 0),
                entityB: RagdollSkeletonFixture.block(of: 1)
            ))
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

    /// The skeleton itself is `RagdollSkeletonFixture`'s, which
    /// `RagdollSelfCollisionTests` builds on too. This suite says nothing about
    /// collision filters, so it takes the fixture's inert static default.
    private static func model(boneNames: [String]) -> NIFCollisionModel {
        RagdollSkeletonFixture.model(boneNames: boneNames)
    }

    private static func bindMatrices(count: Int) -> [float4x4] {
        RagdollSkeletonFixture.bindMatrices(count: count)
    }
}
