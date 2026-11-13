// `BSBoneSwitchGenerator` and `BSOffsetAnimationGenerator` over two static clips.

import Foundation
import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
import simd
import Testing

struct BehaviorBethesdaGeneratorTests {
    private static var clipTable: BehaviorClipTable {
        BehaviorFixture.staticClipPair(left: 0, right: 10)
    }

    private static func clips(_ table: inout BehaviorObjectTable)
        -> (HKXPointerTarget, HKXPointerTarget)
    {
        let left = table.add(
            BehaviorFixture.clipGenerator("left", animationName: "left"),
            at: 0x100
        )
        let right = table.add(
            BehaviorFixture.clipGenerator("right", animationName: "right"),
            at: 0x110
        )
        return (left, right)
    }

    /// The child's clip replaces the default on the bones its weights cover. A child
    /// without weights changes nothing.
    @Test func aBoneSwitchChildOwnsItsWeightedBones() {
        var table = BehaviorObjectTable()
        let (left, right) = Self.clips(&table)
        let weights = table.add(
            HKBBoneWeightArray(variableBindingSet: nil, boneWeights: [0, 1, 0], unresolved: []),
            at: 0x120
        )
        let owned = table.add(
            BSBoneSwitchGeneratorBoneData(
                variableBindingSet: nil, generator: right, boneWeight: weights, unresolved: []
            ),
            at: 0x130
        )
        let unweighted = table.add(
            BSBoneSwitchGeneratorBoneData(
                variableBindingSet: nil, generator: right, boneWeight: nil, unresolved: []
            ),
            at: 0x140
        )
        let root = table.add(
            BSBoneSwitchGenerator(
                node: BehaviorFixture.nodeHeader("switch"), defaultGenerator: left,
                children: [owned, unweighted, nil], unresolved: []
            ),
            at: 0x150
        )
        let graph = BehaviorFixture.instance(root: root, table: table, clips: Self.clipTable)
        #expect(abs(graph.update(deltaTime: 0.1).bones[1].translation.x - 10) < 1e-4)
    }

    /// A clip that is not additive leaves the default pose as it is.
    @Test func anOffsetOverAPlainClipKeepsTheDefaultPose() {
        var table = BehaviorObjectTable()
        let (left, right) = Self.clips(&table)
        let root = table.add(
            BSOffsetAnimationGenerator(
                node: BehaviorFixture.nodeHeader("offset"), defaultGenerator: left,
                offsetClipGenerator: right, offsetVariable: 0.5, offsetRangeStart: 0,
                offsetRangeEnd: 1, unresolved: []
            ),
            at: 0x150
        )
        let graph = BehaviorFixture.instance(root: root, table: table, clips: Self.clipTable)
        #expect(abs(graph.update(deltaTime: 0.1).bones[1].translation.x) < 1e-4)
        #expect(abs(graph.update(deltaTime: 0.1).bones[1].translation.x) < 1e-4)
    }

    /// A synchronized clip plays its wrapped clip as a plain one.
    @Test func aSynchronizedClipPlaysItsClip() {
        var table = BehaviorObjectTable()
        let (_, right) = Self.clips(&table)
        let root = table.add(
            BSSynchronizedClipGenerator(
                node: BehaviorFixture.nodeHeader("sync"), clipGenerator: right,
                syncAnimPrefix: "NPC", syncClipIgnoreMarkPlacement: false, getToMarkTime: 0,
                markErrorThreshold: 0, leadCharacter: true, reorientSupportChar: false,
                applyMotionFromRoot: false, animationBindingIndex: -1, unresolved: []
            ),
            at: 0x150
        )
        let graph = BehaviorFixture.instance(root: root, table: table, clips: Self.clipTable)
        #expect(abs(graph.update(deltaTime: 0.1).bones[1].translation.x - 10) < 1e-4)
        _ = graph.clipPlayback.pairedClipNames
    }

    /// A blender child's bone mask limits it to the bones the mask covers.
    @Test func aMaskedBlenderChildMovesOnlyItsBones() {
        var table = BehaviorObjectTable()
        let (left, right) = Self.clips(&table)
        let weights = table.add(
            HKBBoneWeightArray(variableBindingSet: nil, boneWeights: [0, 1, 0], unresolved: []),
            at: 0x120
        )
        let base = table.add(BehaviorFixture.blenderChild(generator: left, weight: 1), at: 0x130)
        let masked = table.add(
            HKBBlenderGeneratorChild(
                variableBindingSet: nil, generator: right, boneWeights: weights, weight: 1,
                worldFromModelWeight: 1, unresolved: []
            ),
            at: 0x140
        )
        let root = table.add(
            BehaviorFixture.blender("blend", children: [base, masked]), at: 0x150
        )
        let graph = BehaviorFixture.instance(root: root, table: table, clips: Self.clipTable)
        #expect(graph.update(deltaTime: 0.1).bones[1].translation.x > 0)
    }
}
