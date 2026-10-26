// Bone LOD on an actor's rig: past an entry's distance, its bone and every later bone
// keep the pose they had.

@testable import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsMesh
import simd
import Testing

struct ActorBoneLODTests {
    private static let rig = HKASkeleton(
        name: nil,
        bones: ["Root", "Spine", "Head", "Finger", "Camera"].map {
            HKABone(name: $0, lockTranslation: false)
        },
        parentIndices: [-1, 0, 1, 1, 0],
        referencePose: Array(repeating: HKABonePose(transform: matrix_identity_float4x4), count: 5)
    )

    private static let lod = ActorBoneLOD(bones: [
        .init(distance: 768, node: nil, name: "finger"),
        .init(distance: 128, node: nil, name: "Camera"),
        .init(distance: 500, node: nil, name: "No Such Bone")
    ], rig: rig)

    private static func pose(_ x: Float) -> [HKABonePose] {
        let bone = HKABonePose(translation: [x, 0, 0], rotation: simd_quatf(), scale: [1, 1, 1])
        return Array(repeating: bone, count: 5)
    }

    @Test func eachNamedRigBoneBecomesACutoffNearestFirst() throws {
        let lod = try #require(Self.lod)
        #expect(lod.cutoffs.map(\.bone) == [4, 3])
        #expect(lod.firstHeldBone(atDistance: 100) == nil)
        #expect(lod.firstHeldBone(atDistance: 200) == 4)
        #expect(lod.firstHeldBone(atDistance: 1000) == 3)
    }

    @Test func heldBonesKeepTheirLastPoseAndEarlierBonesMove() {
        let held = ActorBoneLOD.holding(Self.pose(2), previous: Self.pose(1), from: 3)
        #expect(held.map(\.translation.x) == [2, 2, 2, 1, 1])
        #expect(ActorBoneLOD.holding(Self.pose(2), previous: [], from: 3).map(\.translation.x)
            == [2, 2, 2, 2, 2])
    }

    @Test func aRigWithoutTheNamedBonesHasNoBoneLOD() {
        #expect(
            ActorBoneLOD(bones: [.init(distance: 10, node: nil, name: "Tail")], rig: Self.rig) ==
                nil
        )
    }
}
