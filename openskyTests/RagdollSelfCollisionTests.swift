// Which of a ragdoll's own bones may touch each other (issue #413).
//
// Two halves. The first pins the filter bits against nif.xml's
// `CollisionFilterFlags` bitfield — biped part in bits 0-4, `No Collision` at
// bit 6, and the part meaningful only on the biped layers. The second pins the
// four admission rules and shows the solver acting on them: an admitted pair of
// overlapping bones pushes apart, a rejected one is not even asked.
//
// Everything is built in code. The vanilla humanoid's own numbers are asserted
// in `RagdollRealDataTests`, which is the half that needs the install.

@testable import opensky
import simd
import Testing

struct RagdollSelfCollisionTests {
    // MARK: - The filter bits

    /// nif.xml: bits 0-4 are the `BipedPart`, and they mean a part only on
    /// `SKYL_BIPED` (8), `SKYL_DEADBIP` (32) and `SKYL_BIPED_NO_CC` (33).
    @Test
    func theBipedPartIsTheLowFiveBitsOnABipedLayer() {
        #expect(NIFCollisionFilter(layer: 8, flags: 9, group: 0).bipedPart == 9)
        #expect(NIFCollisionFilter(layer: 32, flags: 16, group: 0).bipedPart == 16)
        #expect(NIFCollisionFilter(layer: 33, flags: 1, group: 0).bipedPart == 1)
        // Part zero is `P_OTHER`, a part like any other — the vanilla humanoid
        // puts it on `NPC Neck` — so it must not read as "no part".
        #expect(NIFCollisionFilter(layer: 8, flags: 0, group: 0).bipedPart == 0)
        // A static crate carries the same byte and means nothing by it.
        #expect(NIFCollisionFilter(layer: 1, flags: 9, group: 0).bipedPart == nil)
        #expect(NIFCollisionFilter(layer: 12, flags: 9, group: 0).bipedPart == nil)
    }

    /// The three flag bits above the part must not leak into it, and
    /// `No Collision` must be read at bit 6 rather than anywhere else.
    @Test
    func theFlagBitsAboveThePartAreNotPartOfIt() {
        // MOPP Scaled (0x20), No Collision (0x40) and Linked Group (0x80) all
        // set, over part 10.
        let crowded = NIFCollisionFilter(layer: 8, flags: 0xEA, group: 0)
        #expect(crowded.bipedPart == 10)
        #expect(crowded.hasNoCollision)
        let plain = NIFCollisionFilter(layer: 8, flags: 0xAA, group: 0)
        #expect(plain.bipedPart == 10)
        #expect(!plain.hasNoCollision)
    }

    // MARK: - The admission rules

    /// A jointed pair is one hop apart, which is what a constraint means: the
    /// two capsules necessarily overlap at the shared pivot.
    @Test
    func jointedBonesNeverCollide() {
        let filter = Self.chain(boneCount: 4, parts: [1, 2, 3, 4])
        #expect(!filter.admits(0, 1))
        #expect(!filter.admits(1, 2))
        #expect(!filter.admits(2, 3))
    }

    /// Two hops is the pair a shared parent holds together — left thigh against
    /// right thigh at the pelvis, upper arm against spine at the shoulder.
    @Test
    func bonesSharingAJointedNeighbourNeverCollide() {
        let filter = Self.chain(boneCount: 4, parts: [1, 2, 3, 4])
        #expect(!filter.admits(0, 2))
        #expect(!filter.admits(1, 3))
    }

    /// Three hops apart with distinct parts is the first pair admitted, and the
    /// pair list agrees with the predicate.
    @Test
    func distantBonesWithDistinctPartsCollide() {
        let filter = Self.chain(boneCount: 4, parts: [1, 2, 3, 4])
        #expect(filter.admits(0, 3))
        #expect(filter.admits(3, 0))
        #expect(filter.pairs == [RagdollBonePair(0, 3)])
        #expect(filter.pairCount == 1)
    }

    /// Two bodies carrying the same part are the same anatomical part modelled
    /// twice, however far apart the joint graph puts them. The vanilla humanoid
    /// does exactly this with `NPC COM` and `NPC Spine`, both `P_BODY`.
    @Test
    func bonesSharingAPartNeverCollide() {
        let filter = Self.chain(boneCount: 4, parts: [2, 5, 6, 2])
        #expect(!filter.admits(0, 3))
        #expect(filter.pairs.isEmpty)
    }

    /// A body whose filter names no biped layer says nothing about biped
    /// self-collision, so it is admitted into nothing.
    @Test
    func bonesWithoutABipedPartNeverCollide() {
        let filter = Self.chain(boneCount: 4, parts: [1, 2, 3, nil])
        #expect(!filter.admits(0, 3))
        #expect(filter.pairs.isEmpty)
        #expect(RagdollSelfCollision.disabled.pairs.isEmpty)
        #expect(!RagdollSelfCollision.disabled.admits(0, 1))
    }

    /// A bone is never admitted against itself, whatever it is asked with.
    @Test
    func aBoneNeverCollidesWithItself() {
        let filter = Self.chain(boneCount: 4, parts: [1, 2, 3, 4])
        for index in 0 ..< 4 {
            #expect(!filter.admits(index, index))
        }
    }

    /// The builder preserves the part off the decoded body, and drops it on a
    /// body whose filter switched collision off outright.
    @Test
    func theBuilderPreservesThePartAndDropsANoCollisionBody() throws {
        let names = ["Bone0", "Bone1", "Bone2", "Bone3"]
        let definition = try #require(RagdollDefinition(
            model: RagdollSkeletonFixture.model(
                boneNames: names,
                filters: [
                    NIFCollisionFilter(layer: 8, flags: 5, group: 0),
                    NIFCollisionFilter(layer: 8, flags: 6, group: 0),
                    NIFCollisionFilter(layer: 8, flags: 7, group: 0),
                    // Part 8, but with No Collision set over it.
                    NIFCollisionFilter(layer: 8, flags: 8 | 0x40, group: 0)
                ]
            ),
            boneNames: names,
            bindMatrices: RagdollSkeletonFixture.bindMatrices(count: names.count)
        ))
        #expect(definition.bones.map(\.bipedPart) == [5, 6, 7, nil])
        // Bones 0 and 3 are the only pair far enough apart, and the fourth
        // carries no part, so nothing is admitted.
        #expect(definition.selfCollision.pairs.isEmpty)
    }

    // MARK: - The solver acting on them

    /// Two overlapping bones the filter admits push each other apart; the same
    /// two with the filter switched off stay interpenetrating, and the solver
    /// never even generates the contact.
    ///
    /// The pair is bones 0 and 2 of a three-bone ragdoll: 0 and 1 are jointed
    /// end to end, and 2 lies alongside 0 without being jointed to anything,
    /// which is the shape of an arm fallen against a torso.
    @Test
    func anAdmittedOverlapSeparatesAndARejectedOneIsNotAsked() {
        let overlapping = RagdollSelfCollisionFixture.armAcrossTorso()
        #expect(overlapping.selfCollision.admits(0, 2))
        let admitted = RagdollSelfCollisionFixture.run(
            overlapping, selfCollision: overlapping.selfCollision
        )
        #expect(admitted.pairContactCount > 0, "the admitted pair generated no contact")
        let rejected = RagdollSelfCollisionFixture.run(overlapping, selfCollision: .disabled)
        #expect(rejected.pairContactCount == 0)

        let start = RagdollSelfCollisionFixture.initialOverlapOffset
        let separation = simd_distance(admitted.bodies[0].position, admitted.bodies[2].position)
        let unchanged = simd_distance(rejected.bodies[0].position, rejected.bodies[2].position)
        #expect(separation > start, "self-collision did not push the bones apart")
        // Nothing else in the weightless world can move them, so the rejected
        // pair is still exactly where it started.
        #expect(abs(unchanged - start) < 0.01, "something other than the contact moved a bone")
    }

    /// Ordinary clutter is unaffected: every pair of loose bodies still collides,
    /// because the self-collision set only applies to a jointed body list.
    @Test
    func clutterStillCollidesWithItself() {
        var bodies = [
            RagdollFixture.bone(center: SIMD3(0, 0, 100)),
            RagdollFixture.bone(center: SIMD3(4, 0, 100))
        ]
        let stats = DynamicBodySolver.step(
            bodies: &bodies, world: RagdollFixture.emptyWorld, dt: WalkController.fixedTimeStep
        )
        #expect(stats.pairContactCount > 0)
    }

    /// Self-collision must not cost the solver its determinism: the admitted set
    /// is a sorted list and membership is all the step asks of it.
    @Test
    func twoRunsWithSelfCollisionMatchExactly() {
        let definition = RagdollFixture.definition(
            boneCount: 3,
            joints: [RagdollFixture.joint(bodyA: 0, bodyB: 1, limits: .point)],
            parts: [1, 2, 3]
        )
        #expect(definition.selfCollision.pairs == [RagdollBonePair(0, 2), RagdollBonePair(1, 2)])
        var first = RagdollSelfCollisionFixture.instance(of: definition)
        var second = RagdollSelfCollisionFixture.instance(of: definition)
        RagdollFixture.run(&first, world: RagdollFixture.floorWorld(), steps: 240)
        RagdollFixture.run(&second, world: RagdollFixture.floorWorld(), steps: 240)
        #expect(RagdollFixture.trace(first) == RagdollFixture.trace(second))
        #expect(RagdollFixture.isFinite(first))
    }

    /// The panel line names the admitted set, so "nothing is touching" reads
    /// differently from "nothing was ever allowed to".
    @Test
    func theReadoutNamesTheAdmittedSet() {
        var snapshot = RagdollStatsSnapshot()
        snapshot.selfCollisionPairCount = 63
        snapshot.selfContactCount = 4
        #expect(RagdollReadout.selfCollisionText(for: snapshot)
            == "Self-collision: 63 bone pairs admitted, 4 touching")
        snapshot.isSelfCollisionEnabled = false
        #expect(RagdollReadout.selfCollisionText(for: snapshot) == "Self-collision: off")
    }

    // MARK: - Fixture

    /// A chain of `boneCount` bones jointed end to end, with the given parts.
    private static func chain(boneCount: Int, parts: [UInt8?]) -> RagdollSelfCollision {
        let joints = (0 ..< boneCount - 1).map {
            RagdollFixture.joint(bodyA: $0, bodyB: $0 + 1, limits: .point)
        }
        return RagdollFixture.definition(
            boneCount: boneCount, joints: joints, parts: parts
        ).selfCollision
    }
}

/// The bodies the solver half of this suite steps.
enum RagdollSelfCollisionFixture {
    /// One synthetic ragdoll: its bones, its joints, and what its own biped
    /// parts admit.
    struct Fixture {
        let bodies: [DynamicBody]
        let joints: [RagdollJointDefinition]
        let selfCollision: RagdollSelfCollision
    }

    /// How far apart bones 0 and 2 of `armAcrossTorso` start, in engine units.
    /// Less than the two radii together, so they begin interpenetrating.
    static let initialOverlapOffset = RagdollFixture.boneRadius

    /// A world with neither gravity nor a floor, so the only thing that can move
    /// a body is the contact under test.
    static var weightlessWorld: DynamicStepWorld {
        DynamicStepWorld(gravity: .zero)
    }

    /// Three capsule bones: 0 and 1 jointed end to end along x, and 2 lying
    /// alongside 0 without a joint of its own, close enough to overlap it. That
    /// is the shape a self-collision rule has to get right — a limb resting
    /// against a torso it is not jointed to — and it is exactly the pair the
    /// joint-distance rule admits and the 15.6 behaviour ignored.
    static func armAcrossTorso() -> Fixture {
        let origin = SIMD3<Float>(0, 0, 100)
        let spacing = RagdollFixture.boneHalfLength * 2
        let bodies = [
            RagdollFixture.bone(center: origin),
            RagdollFixture.bone(center: origin + SIMD3(spacing, 0, 0)),
            RagdollFixture.bone(center: origin + SIMD3(0, initialOverlapOffset, 0))
        ]
        let joints = [RagdollFixture.joint(bodyA: 0, bodyB: 1, limits: .point)]
        let definition = RagdollFixture.definition(
            boneCount: 3, joints: joints, parts: [1, 2, 3]
        )
        return Fixture(
            bodies: bodies, joints: joints, selfCollision: definition.selfCollision
        )
    }

    /// Steps `fixture` for a second of simulated time under one admitted set.
    ///
    /// The reported bone-against-bone count is the largest any step saw, not the
    /// last one's: a pair that has been pushed apart is no longer touching, so
    /// the final step of a working run reports zero.
    static func run(
        _ fixture: Fixture,
        selfCollision: RagdollSelfCollision
    ) -> (bodies: [DynamicBody], pairContactCount: Int) {
        var bodies = fixture.bodies
        var pairContactCount = 0
        for _ in 0 ..< 120 {
            let stats = DynamicBodySolver.step(
                bodies: &bodies,
                world: weightlessWorld,
                dt: WalkController.fixedTimeStep,
                joints: fixture.joints,
                selfCollision: selfCollision
            )
            pairContactCount = max(pairContactCount, stats.pairContactCount)
        }
        return (bodies: bodies, pairContactCount: pairContactCount)
    }

    /// A ragdoll from a definition's own bind placements, so a suite that cares
    /// about the definition rather than the pose can step one.
    static func instance(of definition: RagdollDefinition) -> RagdollInstance {
        let bodies = definition.bones.map { bone in
            RagdollFixture.bone(
                center: bone.bindBoneMatrix.columns.3.xyz + SIMD3(0, 0, 100)
            )
        }
        return RagdollInstance(definition: definition, bodies: bodies)
    }
}
