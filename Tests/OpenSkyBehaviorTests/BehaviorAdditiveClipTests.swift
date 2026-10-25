// Additive clips: a blender adds them on top of its full children, and a graph that
// ends in one adds it to the reference pose.

import Foundation
import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
import simd
import Testing

struct BehaviorAdditiveClipTests {
    private static let quarterTurn = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))

    private static var clips: BehaviorClipTable {
        BehaviorClipTable(byName: [
            "full": BehaviorStaticClip(samples: [BehaviorFixture.sample(bone: 1, x: 4)]),
            "layer": BehaviorStaticClip(
                samples: [
                    HKABoneTransformSample(
                        boneIndex: 1,
                        pose: BehaviorFixture.bonePose(
                            translation: SIMD3(2, 0, 0), rotation: quarterTurn
                        )
                    )
                ],
                isAdditive: true
            )
        ])
    }

    @Test func aBlenderAddsAnAdditiveChildOnTopOfTheFullOnes() {
        var table = BehaviorObjectTable()
        let full = table.add(
            BehaviorFixture.clipGenerator("full", animationName: "full"),
            at: 0x100
        )
        let layer = table.add(
            BehaviorFixture.clipGenerator("layer", animationName: "layer"), at: 0x110
        )
        let fullChild = table.add(
            BehaviorFixture.blenderChild(generator: full, weight: 1),
            at: 0x120
        )
        let layerChild = table.add(
            BehaviorFixture.blenderChild(generator: layer, weight: 0.5), at: 0x130
        )
        let root = table.add(
            BehaviorFixture.blender("blend", children: [fullChild, layerChild]), at: 0x140
        )
        let graph = BehaviorFixture.instance(root: root, table: table, clips: Self.clips)
        let bones = graph.update(deltaTime: 1 / 30).bones

        // Half the layer: 4 + 2 * 0.5 along x, and half the quarter turn.
        #expect(abs(bones[1].translation.x - 5) < 1e-4)
        #expect(abs(bones[1].rotation.angle - .pi / 4) < 1e-4)
        // The layer has no track for bone 2, so the bone keeps the reference pose.
        #expect(bones[2].translation == SIMD3(0, 20, 0))
    }

    @Test func aGraphThatEndsInAnAdditiveClipAddsItToTheReferencePose() {
        var table = BehaviorObjectTable()
        let root = table.add(
            BehaviorFixture.clipGenerator("layer", animationName: "layer"), at: 0x100
        )
        let graph = BehaviorFixture.instance(root: root, table: table, clips: Self.clips)
        let bones = graph.update(deltaTime: 1 / 30).bones

        #expect(abs(simd_distance(bones[1].translation, SIMD3(2, 10, 0))) < 1e-4)
        #expect(abs(bones[1].rotation.angle - .pi / 2) < 1e-4)
    }

    @Test func anUnchangedLayerLeavesThePoseAsItWas() {
        let base = BehaviorFixture.bonePose(translation: SIMD3(1, 2, 3), rotation: Self.quarterTurn)
        let result = BehaviorPoseMath.adding(BehaviorPoseMath.unchangedBone, to: base, weight: 1)
        #expect(result == base)
    }
}
