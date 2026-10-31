// Script links between two ragdolls, and pins of a bone or a loose body to a fixed
// point: held while they simulate, dropped when a ragdoll stops. Synthetic bodies only.

import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyPhysics
import simd
import Testing

struct RagdollLinkTests {
    private static let left = ReferenceKey.generated(1)
    private static let right = ReferenceKey.generated(2)
    private static let cell = CellSceneLocation.interior(FormID(0x10))

    private static func world() -> RagdollWorld {
        var world = RagdollWorld()
        world.add(RagdollFixture.pair(), for: left, in: cell)
        world.add(RagdollFixture.pair(origin: SIMD3(100, 0, 100)), for: right, in: cell)
        return world
    }

    private static let link = RagdollLink(
        first: PhysicsLinkEnd(reference: left, node: "bone1"),
        second: PhysicsLinkEnd(reference: right, node: "Bone0")
    )

    private static func gap(in world: RagdollWorld) -> Float {
        guard
            let first = world.instance(for: left)?.bodies[1],
            let second = world.instance(for: right)?.bodies[0]
        else { return .infinity }
        return simd_distance(first.position, second.position)
    }

    @Test func aLinkPullsTheTwoBonesTogether() {
        var world = Self.world()
        let before = Self.gap(in: world)
        let linked = world.addLink(Self.link)
        #expect(linked)
        for _ in 0 ..< 240 {
            world.advance(by: PhysicsStep.fixedTimeStep, world: RagdollFixture.emptyWorld)
        }
        #expect(Self.gap(in: world) < before / 4)
    }

    @Test func aLinkNeedsTwoLiveBonesAndEndsWithItsRagdoll() {
        var world = Self.world()
        let missing = RagdollLink(
            first: PhysicsLinkEnd(reference: Self.left, node: "Hand"), second: Self.link.second
        )
        let linkedMissing = world.addLink(missing)
        #expect(!linkedMissing)
        let linkedOnce = world.addLink(Self.link)
        #expect(linkedOnce)
        let linkedAgain = world.addLink(Self.link)
        #expect(linkedAgain)
        #expect(world.links.count == 1)
        let removed = world.removeLinks(Self.link.second, Self.link.first)
        #expect(removed)
        let removedAgain = world.removeLinks(Self.link.first, Self.link.second)
        #expect(!removedAgain)
        world.addLink(Self.link)
        world.remove(Self.right)
        #expect(world.links.isEmpty)
    }

    @Test func aPinHoldsABoneAndALooseBodyAtTheirPoint() {
        var world = Self.world()
        let point = SIMD3<Float>(24, 0, 100)
        let peg = PhysicsLinkEnd(reference: .generated(9), node: "AttachDummy")
        let pinnedBone = world.addPin(PhysicsPin(end: Self.link.first, partner: peg, point: point))
        #expect(pinnedBone)
        for _ in 0 ..< 240 {
            world.advance(by: PhysicsStep.fixedTimeStep, world: RagdollFixture.emptyWorld)
        }
        let held = world.instance(for: Self.left)?.bodies[1].position ?? .zero
        #expect(simd_distance(held, point) < RagdollFixture.boneHalfLength)
        let unpinnedBone = world.removeLinks(peg, Self.link.first)
        #expect(unpinnedBone)

        var loose = DynamicBodyWorld()
        let key = ReferenceKey.generated(3)
        loose.add(DynamicBodyPlacement(
            key: key, reference: FormID(0x300), definition: RagdollFixture.bone(center: point)
                .definition, originPosition: point, orientation: .identityRotation
        ), in: Self.cell)
        let end = PhysicsLinkEnd(reference: key, node: "Key")
        let pinnedLoose = loose.addPin(PhysicsPin(end: end, partner: peg, point: point))
        #expect(pinnedLoose)
        for _ in 0 ..< 240 {
            loose.advance(by: PhysicsStep.fixedTimeStep, world: RagdollFixture.emptyWorld)
        }
        #expect(simd_distance(loose.body(for: key)?.position ?? .zero, point) < 1)
        let unpinnedLoose = loose.removePins(peg, end)
        #expect(unpinnedLoose)
    }
}
