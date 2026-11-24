// Each posed ragdoll body becomes a world capsule, which the actor camera fade sweeps
// against (docs/engine/actor-camera-fade.md#which-actor-fades).

import OpenSkyEngineTesting
import OpenSkyFormatsCore
@testable import OpenSkyPhysics
import simd
import Testing

struct RagdollWorldCapsulesTests {
    private static func ragdoll(
        _ volumes: [(name: String, volume: DynamicCollisionVolume)]
    ) -> RagdollDefinition {
        let bones = volumes.enumerated().map { index, entry in
            RagdollBoneDefinition(
                boneName: entry.name,
                boneIndex: index,
                body: DynamicBodyDefinition(volumes: [entry.volume], mass: 4),
                bindBoneMatrix: MatrixMath.translation(SIMD3(0, 0, 20))
            )
        }
        return RagdollDefinition(bones: bones, joints: [])
    }

    @Test func aPosedCapsuleMovesAndScalesIntoTheWorld() {
        let spine = "NPC Spine [Spn0]"
        let ragdoll = Self.ragdoll([
            (spine, .radial(first: SIMD3(0, 0, -10), second: SIMD3(0, 0, 10), radius: 3)),
            ("NPC Head [Head]", .radial(first: .zero, second: .zero, radius: 5))
        ])
        let capsules = ragdoll.worldCapsules(
            boneToActor: [spine: MatrixMath.translation(SIMD3(5, 0, 30))],
            actorToWorld: MatrixMath.translation(SIMD3(100, 0, 0)) * MatrixMath.scale(uniform: 2),
            scale: 2
        )
        #expect(capsules == [RagdollWorldCapsule(
            start: SIMD3(110, 0, 0), end: SIMD3(110, 0, 40), radius: 6
        )])
    }

    @Test func aHullBecomesTheSphereAroundItsPoints() {
        let bone = "NPC Pelvis [Pelv]"
        let points: [SIMD3<Float>] = [SIMD3(-4, 0, 0), SIMD3(4, 0, 0), SIMD3(0, 3, 0)]
        let ragdoll = Self.ragdoll([(bone, .hull(points: points, planes: []))])
        let capsules = ragdoll.worldCapsules(
            boneToActor: [bone: MatrixMath.translation(SIMD3(0, 0, 20))],
            actorToWorld: matrix_identity_float4x4, scale: 1
        )
        #expect(capsules.count == 1)
        #expect(capsules.first.map { simd_distance($0.start, SIMD3(0, 1, 0)) < 1e-5 } == true)
        #expect(capsules.first.map { abs($0.radius - sqrt(17)) < 1e-5 } == true)
    }
}
