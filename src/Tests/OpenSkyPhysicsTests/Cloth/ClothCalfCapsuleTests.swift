// The cape's calf capsules come from the calf ragdoll bodies, at twice their radius
// (docs/engine/cape-cloth.md#collision).

import OpenSkyEngineTesting
import OpenSkyFormatsCore
@testable import OpenSkyPhysics
import simd
import Testing

struct ClothCalfCapsuleTests {
    private static func ragdoll(names: [String]) -> RagdollDefinition {
        let volume = DynamicCollisionVolume.radial(
            first: SIMD3(0, 0, -10), second: SIMD3(0, 0, 10), radius: 3
        )
        let bones = names.enumerated().map { index, name in
            RagdollBoneDefinition(
                boneName: name,
                boneIndex: index,
                body: DynamicBodyDefinition(volumes: [volume], mass: 4),
                bindBoneMatrix: MatrixMath.translation(SIMD3(0, 0, 20))
            )
        }
        return RagdollDefinition(bones: bones, joints: [])
    }

    @Test func aCalfBodyBecomesACapsuleAtItsPoseWithTwiceTheRadius() {
        let left = "NPC L Calf [LClf]"
        let pose = [left: MatrixMath.translation(SIMD3(5, 0, 30))]
        let capsules = ClothCapsule.calves(
            ragdoll: Self.ragdoll(names: [left, "NPC Spine [Spn0]"]),
            boneToActor: pose,
            actorToWorld: MatrixMath.translation(SIMD3(100, 0, 0))
        )
        #expect(capsules == [ClothCapsule(
            start: SIMD3(105, 0, 0), end: SIMD3(105, 0, 20), radius: 6
        )])
    }

    @Test func aCalfThePoseDoesNotHoldGetsNoCapsule() {
        let capsules = ClothCapsule.calves(
            ragdoll: Self.ragdoll(names: ["NPC R Calf [RClf]"]),
            boneToActor: [:],
            actorToWorld: matrix_identity_float4x4
        )
        #expect(capsules.isEmpty)
    }
}
