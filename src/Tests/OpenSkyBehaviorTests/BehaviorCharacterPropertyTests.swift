// Character-property bindings and pose matching, run through a graph instance.

import Foundation
@testable import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
import simd
import Testing

struct BehaviorCharacterPropertyTests {
    private static let step: Float = 0.1

    /// One blender child whose bone weights come from the character property "Mask".
    private static func maskedGraph() -> BehaviorGraphInstance {
        var table = BehaviorObjectTable()
        let clip = table.add(
            BehaviorFixture.clipGenerator("pose", animationName: "pose"),
            at: 0x100
        )
        let bindings = table.add(
            BehaviorFixture.bindingSet([BehaviorBindingSpec("boneWeights", 0, bindingType: 1)]),
            at: 0x180
        )
        let child = table.add(
            BehaviorFixture.blenderChild(generator: clip, weight: 1, bindingSet: bindings),
            at: 0x200
        )
        let root = table.add(BehaviorFixture.blender("mask", children: [child]), at: 0x300)
        return BehaviorFixture.instance(
            root: root,
            table: table,
            data: BehaviorFixture.graphData(characterProperties: ["Mask"]),
            clips: BehaviorClipTable(byName: [
                "pose": BehaviorStaticClip(samples: [BehaviorFixture.sample(bone: 1, x: 7)])
            ])
        )
    }

    @Test func withoutTheCharacterTheClipPosesEveryBone() {
        let bones = Self.maskedGraph().update(deltaTime: Self.step).bones
        #expect(bones[1].translation.x == 7)
    }

    /// A bone weight of 0 on the only child drops that bone to the reference pose.
    @Test func aCharacterPropertyBindsTheChildsBoneWeights() {
        let graph = Self.maskedGraph()
        graph.characterProperties = BehaviorCharacterProperties(
            values: [:], boneWeights: ["mask": [1, 0, 1]]
        )
        let bones = graph.update(deltaTime: Self.step).bones
        #expect(bones[1].translation == SIMD3(0, 10, 0))
    }

    @Test func propertiesAreFoundByNameInAnyCase() {
        let properties = BehaviorCharacterProperties(
            values: ["IsFemale": .bool(true)], boneWeights: ["Mask": [1]]
        )
        #expect(properties.value(named: "isfemale") == .bool(true))
        #expect(properties.boneWeights(named: "MASK") == [1])
        #expect(properties.holdsObject(named: "mask"))
        #expect(!properties.holdsObject(named: "IsFemale"))
    }

    // MARK: - Pose matching

    /// Three root bones, so a bone's local pose is its model pose. Ragdoll bone i is bone i.
    private static var flatSkeleton: BehaviorSkeleton {
        var skeleton = BehaviorSkeleton(
            referencePose: (0 ..< 3).map { _ in BehaviorFixture.bonePose(translation: SIMD3()) },
            parentIndices: [-1, -1, -1]
        )
        skeleton.ragdollBones = [0, 1, 2]
        return skeleton
    }

    /// Bone 1 along x and bone 2 along +y or -y: lying on the back or on the front.
    private static func lying(side: Float) -> [HKABoneTransformSample] {
        [
            BehaviorFixture.sample(bone: 1, x: 1),
            HKABoneTransformSample(
                boneIndex: 2, pose: BehaviorFixture.bonePose(translation: SIMD3(0, side, 0))
            )
        ]
    }

    private static func matcher(children: [HKXPointerTarget?]) -> HKBPoseMatchingGenerator {
        HKBPoseMatchingGenerator(
            node: BehaviorFixture.nodeHeader("matcher"),
            blender: BehaviorFixture.blender("matcher", children: children).blender,
            worldFromModelRotation: SIMD4(0, 0, 0, 1),
            blendSpeed: 2,
            minSpeedToSwitch: 0,
            minSwitchTimeNoError: 0,
            minSwitchTimeFullError: 0,
            startPlayingEventId: 0,
            startMatchingEventId: -1,
            rootBoneIndex: 0,
            otherBoneIndex: 1,
            anotherBoneIndex: 2,
            pelvisIndex: 0,
            mode: 0,
            unresolved: []
        )
    }

    private static func matchingGraph() -> BehaviorGraphInstance {
        var table = BehaviorObjectTable()
        let children = ["back", "front"].enumerated().map { index, name in
            let clip = table.add(
                BehaviorFixture.clipGenerator(name, animationName: name), at: 0x100 + index * 0x10
            )
            return table.add(
                BehaviorFixture.blenderChild(generator: clip, weight: 0), at: 0x200 + index * 0x10
            )
        }
        let root = table.add(matcher(children: children), at: 0x300)
        return BehaviorGraphInstance(
            root: root,
            data: BehaviorFixture.graphData(events: ["play"]),
            source: table,
            skeleton: flatSkeleton,
            clips: BehaviorClipTable(byName: [
                "back": BehaviorStaticClip(samples: lying(side: 1)),
                "front": BehaviorStaticClip(samples: lying(side: -1))
            ])
        )
    }

    private static func live(side: Float) -> [HKABonePose] {
        BehaviorPoseMath.applying(lying(side: side), to: flatSkeleton.referencePose)
    }

    @Test(arguments: [Float(1), -1])
    func theFirstUpdatePicksTheClipThatMatchesTheLivePose(side: Float) {
        let graph = Self.matchingGraph()
        graph.characterContext.livePose = Self.live(side: side)
        let bones = graph.update(deltaTime: Self.step).bones
        #expect(bones[2].translation.y == side)
    }

    /// A switch fades in at `m_blendSpeed`: 2 per second is 0.2 of the new clip after 0.1 s.
    @Test func aBetterMatchLaterFadesIn() {
        let graph = Self.matchingGraph()
        graph.characterContext.livePose = Self.live(side: 1)
        graph.update(deltaTime: Self.step)
        graph.characterContext.livePose = Self.live(side: -1)
        graph.update(deltaTime: Self.step)
        let bones = graph.update(deltaTime: Self.step).bones
        #expect(abs(bones[2].translation.y - 0.6) < 1e-4)
    }

    @Test func thePlayEventStopsMatching() {
        let graph = Self.matchingGraph()
        graph.characterContext.livePose = Self.live(side: 1)
        graph.update(deltaTime: Self.step)
        graph.raiseEvent(named: "play")
        graph.update(deltaTime: Self.step)
        graph.characterContext.livePose = Self.live(side: -1)
        graph.update(deltaTime: Self.step)
        #expect(graph.update(deltaTime: Self.step).bones[2].translation.y == 1)
    }
}
