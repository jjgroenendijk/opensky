// Bone modifiers and generators that work in model space: foot IK over a leg
// rig, the physics hand-offs, and the reference pose generator. All rigs are synthetic.

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

    @Test func footIkSwitchedOffLeavesTheLegOnRaisedGround() {
        let graph = legGraph(FlatGround(height: 10))
        graph.characterContext.footIk = false
        let bones = graph.update(deltaTime: 1 / 30).bones
        #expect(simd_distance(ankle(bones), SIMD3(0, 0, 5)) < 1e-3)
        #expect(graph.footIkError == SIMD3())
    }

    private func physicsRequests(after modifier: any HKBClass) -> BehaviorPhysicsRequests {
        var table = BehaviorObjectTable()
        let target = table.add(modifier, at: 0x100)
        let root = table.add(
            BehaviorFixture.modifierGenerator("root", modifier: target, generator: nil), at: 0x110
        )
        let graph = BehaviorFixture.instance(root: root, table: table)
        _ = graph.update(deltaTime: 1 / 30)
        return graph.physicsRequests
    }

    @Test func keyframeBonesRequestsOnlyValidBones() {
        let info = { (bone: Int, valid: Bool) in
            HKBKeyframeInfo(
                keyframedPosition: SIMD4(), keyframedRotation: SIMD4(0, 0, 0, 1),
                boneIndex: bone, isValid: valid
            )
        }
        let requests = physicsRequests(after: HKBKeyframeBonesModifier(
            modifier: BehaviorFixture.modifierHeader("keyframe"),
            keyframeInfo: [info(2, true), info(1, false), info(0, true)],
            keyframedBonesList: nil, unresolved: []
        ))
        #expect(requests.keyframedBones == [0, 2])
    }

    @Test func getUpHandsItsTimingToPhysics() throws {
        let requests = physicsRequests(after: HKBGetUpModifier(
            modifier: BehaviorFixture.modifierHeader("getUp"),
            groundNormal: SIMD4(0, 0, 1, 0), duration: 1.5, alignWithGroundDuration: 0.5,
            rootBoneIndex: 1, otherBoneIndex: -1, anotherBoneIndex: -1, unresolved: []
        ))
        let getUp = try #require(requests.getUp)
        #expect(getUp.groundNormal == SIMD3(0, 0, 1))
        #expect([getUp.duration, getUp.alignDuration] == [1.5, 0.5])
        #expect(getUp.rootBoneIndex == 1)
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
