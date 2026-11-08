// Script links from a loose body to another loose body and to a ragdoll bone: the
// pivots come together, and removing the link frees them. Synthetic bodies only.

import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyPhysics
import simd
import Testing

struct LooseBodyLinkTests {
    private static let cell = CellSceneLocation.interior(FormID(0x10))
    private static let ragdoll = ReferenceKey.generated(1)

    private static func addLoose(
        _ key: ReferenceKey, _ reference: UInt32, at point: SIMD3<Float>,
        to world: inout DynamicBodyWorld
    ) {
        world.add(DynamicBodyPlacement(
            key: key, reference: FormID(reference),
            definition: RagdollFixture.bone(center: point).definition,
            originPosition: point, orientation: .identityRotation
        ), in: cell)
    }

    @Test func twoLooseBodiesFallTogetherOnceLinked() {
        var loose = DynamicBodyWorld()
        let key = ReferenceKey.generated(3)
        let chain = ReferenceKey.generated(4)
        let peg = PhysicsLinkEnd(reference: .generated(9), node: "AttachDummy")
        let point = SIMD3<Float>(0, 0, 200)
        Self.addLoose(key, 0x300, at: point, to: &loose)
        Self.addLoose(chain, 0x301, at: point + SIMD3(40, 0, 0), to: &loose)
        let keyEnd = PhysicsLinkEnd(reference: key, node: "Key")
        let chainEnd = PhysicsLinkEnd(reference: chain, node: "Chain")
        let pinned = loose.addPin(PhysicsPin(end: keyEnd, partner: peg, point: point))
        let linked = loose.addLink(PhysicsLink(first: chainEnd, second: keyEnd))
        #expect(pinned && linked)
        for _ in 0 ..< 240 {
            loose.advance(by: PhysicsStep.fixedTimeStep, world: RagdollFixture.emptyWorld)
        }
        let held = loose.body(for: chain)?.position ?? .zero
        #expect(simd_distance(held, point) < 4, "the linked body hangs from the pinned one")
        let removed = loose.removePins(keyEnd, chainEnd)
        #expect(removed)
        #expect(loose.links.isEmpty)
    }

    @Test func aLooseBodyHangsFromARagdollBone() {
        var ragdolls = RagdollWorld()
        ragdolls.add(RagdollFixture.pair(), for: Self.ragdoll, in: Self.cell)
        let bone = PhysicsLinkEnd(reference: Self.ragdoll, node: "Bone0")
        let start = ragdolls.instance(for: Self.ragdoll)?.bodies[0].position ?? .zero
        var loose = DynamicBodyWorld()
        let key = ReferenceKey.generated(3)
        Self.addLoose(key, 0x300, at: start + SIMD3(60, 0, 0), to: &loose)
        let end = PhysicsLinkEnd(reference: key, node: "Lantern")
        #expect(ragdolls.hasBody(bone))
        let linked = loose.addRagdollLink(PhysicsLink(first: end, second: bone))
        #expect(linked)
        for _ in 0 ..< 240 {
            ragdolls.advance(by: PhysicsStep.fixedTimeStep, world: RagdollFixture.emptyWorld)
            loose.advance(by: PhysicsStep.fixedTimeStep, world: RagdollFixture.emptyWorld)
            ragdolls.solveLinks(to: &loose, frameTime: PhysicsStep.fixedTimeStep)
        }
        let boneAt = ragdolls.instance(for: Self.ragdoll)?.bodies[0].position ?? .zero
        let looseAt = loose.body(for: key)?.position ?? .zero
        #expect(simd_distance(boneAt, looseAt) < 2)
        let removed = loose.removePins(bone, end)
        #expect(removed)
        #expect(loose.ragdollLinks.isEmpty)
    }
}
