// An effect model's posed bones: its graph's rig first, then the nodes its own
// controllers move, all in the model frame.

import OpenSkyFormatsAnimation
import OpenSkyFormatsMesh
@testable import OpenSkyObjectAnimation
import simd
import Testing

struct EffectPoseRigTests {
    private static func bone(_ translation: SIMD3<Float>) -> HKABonePose {
        HKABonePose(
            translation: translation, rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), scale: [
                1,
                1,
                1
            ]
        )
    }

    private static let graph = HKASkeleton(
        name: nil,
        bones: ["Root", "Arm"].map { HKABone(name: $0, lockTranslation: false) },
        parentIndices: [-1, 0],
        referencePose: [bone([0, 0, 1]), bone([2, 0, 0])]
    )

    @Test @MainActor func theGraphBonesComeFirstThenTheMovedNodesInTheModelFrame() throws {
        let file = try NodeControllerCoordinatorTests.file(flags: 0xC)
        let nodes = try #require(try NodeControllerRig(file: file))
        let rig = try #require(EffectPoseRig(nodes: nodes, graph: Self.graph))
        #expect(rig.skeleton.boneNames == ["Root", "Arm", "Wheel"])
        #expect(simd_distance(rig.skeleton.referencePose[1].translation, [2, 0, 1]) < 1e-4)
        var animator = NIFNodeAnimator(animation: nodes.animation)
        animator.step(deltaTime: 0.5)
        let raised = [Self.bone([0, 0, 5]), Self.bone([2, 0, 0])]
        let poses = rig.bonePoses(graph: raised, animator: animator)
        #expect(simd_distance(poses[1].translation, [2, 0, 5]) < 1e-4)
        #expect(abs(poses[2].translation.x - 5) < 1e-4)
    }

    @Test func aBillboardBelowAGraphBoneRidesThatBoneWhenTheGraphMovesIt() throws {
        let rest = NIFNodeTransform(
            translation: [0, 0, 0], rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), scale: 1
        )
        let glow = NIFNodeTransform(
            translation: [1, 0, 0], rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), scale: 1
        )
        let animation = NIFNodeAnimation(
            nodes: [
                .init(name: "Scene", parent: nil, rest: rest),
                .init(name: "Arm", parent: 0, rest: NIFNodeTransform(
                    translation: [2, 0, 1], rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                    scale: 1
                )),
                .init(name: "Glow", parent: 1, rest: glow, billboardMode: 4)
            ],
            controllers: []
        )
        let nodes = try #require(NodeControllerRig(animation: animation, lagOnly: true))
        let rig = try #require(EffectPoseRig(nodes: nodes, graph: Self.graph))
        #expect(rig.addsNodes)
        #expect(rig.skeleton.boneNames == ["Root", "Arm", "Glow"])
        let animator = NIFNodeAnimator(animation: animation)
        let raised = [Self.bone([0, 0, 5]), Self.bone([2, 0, 0])]
        let poses = rig.bonePoses(graph: raised, animator: animator)
        // The arm moved from (2, 0, 1) to (2, 0, 5), so the glow rides 4 units up with it.
        #expect(simd_distance(poses[2].translation, [3, 0, 5]) < 1e-4)
    }

    @Test func aModelWithNeitherAGraphNorAMovingNodeIsNotPosed() {
        #expect(EffectPoseRig(nodes: nil, graph: nil) == nil)
    }
}
