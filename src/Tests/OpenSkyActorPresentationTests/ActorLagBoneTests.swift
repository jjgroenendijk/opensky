// A creature's lag bone trails the rig bone it hangs from as the actor moves, no further
// than its maximum distance, and comes back to rest once the actor stands still.

@testable import OpenSkyActorPresentation
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import simd
import Testing

struct ActorLagBoneTests {
    private static let rig = ActorLagBoneRig(bones: [.init(
        name: "LagBone", parent: "Body",
        rest: NIFNodeTransform(
            translation: [0, 0, 10], rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), scale: 1
        ),
        lag: NIFLagBone(linearVelocity: 1, linearRotation: 1, maximumDistance: 15)
    )])

    private static let bones = SkeletonBoneIndex(names: ["Body"])
    private static let index = SkeletonBoneIndex(names: ["Body", "LagBone"])

    private static func at(_ x: Float) -> float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4(x, 0, 0, 1)
        return matrix
    }

    @Test func theLagBoneTrailsTheMovingActorThenSettles() {
        var state = ActorLagBoneState()
        let pose = SkeletonPose(bones: Self.bones, matrices: [matrix_identity_float4x4])
        _ = state.pose(
            pose,
            on: (Self.rig, Self.index),
            placement: Self.at(0),
            deltaTime: 0.1
        )
        let moved = state.pose(
            pose, on: (Self.rig, Self.index), placement: Self.at(100), deltaTime: 0.1
        )
        // The gap of 100 drops to 15 at once, then closes 15 * 0.1: 13.5 behind.
        let lag = moved.matrices[1].columns.3
        #expect(abs(lag.x + 13.5) < 1e-3)
        #expect(abs(lag.z - 10) < 1e-3)
        #expect(abs((state.offsets["LagBone"] ?? 0) - 13.5) < 1e-3)
        for _ in 0 ..< 400 {
            _ = state.pose(
                pose, on: (Self.rig, Self.index), placement: Self.at(100), deltaTime: 0.1
            )
        }
        #expect((state.offsets["LagBone"] ?? 1) < 0.01)
    }
}
