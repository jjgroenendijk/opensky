// Bone modifiers and generators that work in model space: foot IK over a leg
// rig, and the reference pose generator. All rigs are synthetic.

import Foundation
@testable import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
import simd
import Testing

/// Ground at one fixed model-space height everywhere.
private struct FlatGround: BehaviorGroundProbe {
    let height: Float

    func groundHeight(at _: SIMD3<Float>, up _: Float, down _: Float) -> Float? {
        height
    }

    func firstHit(from _: SIMD3<Float>, to _: SIMD3<Float>, radius _: Float) -> Float? {
        nil
    }
}

struct BehaviorBoneModifierTests {
    /// Root, hip, knee, ankle. The knee sits a little forward so the leg bends
    /// in a known plane; the ankle rests at model height 5.
    private static let legSkeleton = BehaviorSkeleton(
        referencePose: [
            BehaviorFixture.bonePose(translation: SIMD3(0, 0, 0)),
            BehaviorFixture.bonePose(translation: SIMD3(0, 0, 100)),
            BehaviorFixture.bonePose(translation: SIMD3(0, 5, -50)),
            BehaviorFixture.bonePose(translation: SIMD3(0, -5, -45))
        ],
        parentIndices: [-1, 0, 1, 2]
    )

    private static func footIk() -> HKBFootIkModifier {
        HKBFootIkModifier(
            modifier: BehaviorFixture.modifierHeader("footIk"),
            gains: HKBFootIkGains(gains: [1] + Array(repeating: 0, count: 11)),
            legs: [HKBFootIkModifierLeg(
                kneeAxisLS: SIMD4(1, 0, 0, 0), footEndLS: SIMD4(),
                ungroundedEvent: HKBEventProperty(id: -1, payload: nil),
                footPlantedAnkleHeightMS: 0, footRaisedAnkleHeightMS: 0,
                maxAnkleHeightMS: 0, minAnkleHeightMS: 0, maxKneeAngleDegrees: 180,
                minKneeAngleDegrees: 0, maxAnkleAngleDegrees: 90,
                hipIndex: 1, kneeIndex: 2, ankleIndex: 3
            )],
            raycastDistanceUp: 50, raycastDistanceDown: 50, originalGroundHeightMS: 0,
            verticalOffset: 0, useTrackData: false, lockFeetWhenPlanted: false, alignMode: 0,
            unresolved: []
        )
    }

    private func legGraph(_ ground: (any BehaviorGroundProbe)?) -> BehaviorGraphInstance {
        var table = BehaviorObjectTable()
        let modifier = table.add(Self.footIk(), at: 0x100)
        let root = table.add(
            BehaviorFixture.modifierGenerator("root", modifier: modifier, generator: nil), at: 0x110
        )
        let graph = BehaviorGraphInstance(
            root: root, data: BehaviorFixture.graphData(), source: table,
            skeleton: Self.legSkeleton, clips: EmptyBehaviorClipSource()
        )
        graph.characterContext = BehaviorCharacterContext(ground: ground)
        return graph
    }

    private func ankle(_ bones: [HKABonePose]) -> SIMD3<Float> {
        BehaviorModelPose(BehaviorPose(bones: bones), skeleton: Self.legSkeleton).translations[3]
    }

    @Test func footIkLeavesTheLegAloneWithoutAProbe() {
        let bones = legGraph(nil).update(deltaTime: 1 / 30).bones
        #expect(simd_distance(ankle(bones), SIMD3(0, 0, 5)) < 1e-3)
    }

    @Test func footIkLiftsTheAnkleOntoRaisedGround() {
        let bones = legGraph(FlatGround(height: 10)).update(deltaTime: 1 / 30).bones
        #expect(simd_distance(ankle(bones), SIMD3(0, 0, 15)) < 0.05)
    }

    @Test func referencePoseGeneratorGivesTheRestPose() {
        var table = BehaviorObjectTable()
        let root = table.add(
            HKBReferencePoseGenerator(node: BehaviorFixture.nodeHeader("rest"), unresolved: []),
            at: 0x100
        )
        let graph = BehaviorFixture.instance(root: root, table: table)
        #expect(graph.update(deltaTime: 1 / 30).bones == BehaviorFixture.skeleton().referencePose)
        #expect(graph.tally.unevaluatedGenerators.isEmpty)
    }
}
