// The blender flags: a parametric blend plays the two children around its parameter, and
// a synced blender plays every child at the speed that ends their loops together.

import Foundation
@testable import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
import Testing

struct BehaviorBlenderFlagTests {
    private static let parametric = BehaviorBlenderFlag.parametricBlend

    @Test func aParameterBetweenTwoChildrenSharesTheirWeight() {
        let positions: [Float] = [0, 100, 300]
        #expect(BehaviorParametricBlend.weights(positions: positions, parameter: 50) == [
            0.5,
            0.5,
            0
        ])
        #expect(BehaviorParametricBlend.weights(positions: positions, parameter: 200) == [
            0,
            0.5,
            0.5
        ])
        #expect(BehaviorParametricBlend.weights(positions: positions, parameter: -10) == [1, 0, 0])
        #expect(BehaviorParametricBlend.weights(positions: positions, parameter: 400) == [0, 0, 1])
    }

    @Test func childrenAreFoundInParameterOrderNotDeclaredOrder() {
        let weights = BehaviorParametricBlend.weights(positions: [300, 0, 100], parameter: 250)
        #expect(weights == [0.75, 0, 0.25])
    }

    @Test func aCyclicParameterBlendsAcrossTheSeam() {
        let positions: [Float] = [0, 90, 180, 270]
        let range: ClosedRange<Float> = 0 ... 360
        let late = BehaviorParametricBlend.weights(
            positions: positions,
            parameter: 315,
            cyclic: range
        )
        #expect(late == [0.5, 0, 0, 0.5])
        let wrapped = BehaviorParametricBlend.weights(
            positions: positions,
            parameter: -45,
            cyclic: range
        )
        #expect(wrapped == [0.5, 0, 0, 0.5])
        let full = BehaviorParametricBlend.weights(
            positions: positions,
            parameter: 360,
            cyclic: range
        )
        #expect(full == [1, 0, 0, 0])
    }

    /// Walk at 0, run at 100, sprint at 300: a speed of 50 is half walk, half run, and the
    /// sprint clip does not play at all.
    @Test func aParametricBlenderPlaysOnlyTheChildrenAroundItsParameter() throws {
        var table = BehaviorObjectTable()
        let names = ["walk", "run", "sprint"]
        let clips = names.enumerated().map { index, name in
            table.add(
                BehaviorFixture.clipGenerator(name, animationName: name),
                at: 0x100 + index * 0x10
            )
        }
        let children = zip(clips, [Float(0), 100, 300]).enumerated().map { index, pair in
            table.add(
                BehaviorFixture.blenderChild(generator: pair.0, weight: pair.1),
                at: 0x200 + index * 0x10
            )
        }
        let root = table.add(
            BehaviorStateMachineFixture.syncedBlender(
                "locomotion", children: children, flags: Self.parametric, parameter: 50
            ),
            at: 0x300
        )
        let graph = BehaviorFixture.instance(
            root: root,
            table: table,
            clips: BehaviorClipTable(byName: [
                "walk": BehaviorStaticClip(samples: [BehaviorFixture.sample(bone: 1, x: 10)]),
                "run": BehaviorStaticClip(samples: [BehaviorFixture.sample(bone: 1, x: 20)]),
                "sprint": BehaviorStaticClip(samples: [BehaviorFixture.sample(bone: 1, x: 90)])
            ])
        )
        let bones = graph.update(deltaTime: 0.1).bones
        #expect(try abs(#require(bones[safe: 1]).translation.x - 15) < 1e-4)
        #expect(graph.nodeStates[clips[2]]?.hasSeeded != true)
    }

    /// Loops of 1 s and 2 s at equal weight share a 1.5 s cycle: after 0.3 s both sit at
    /// phase 0.2, the short one at 0.2 s and the long one at 0.4 s.
    @Test func aSyncedBlenderEndsItsChildrensLoopsTogether() throws {
        var table = BehaviorObjectTable()
        let short = table.add(
            BehaviorFixture.clipGenerator("short", animationName: "short"),
            at: 0x100
        )
        let long = table.add(
            BehaviorFixture.clipGenerator("long", animationName: "long"),
            at: 0x110
        )
        let children = [
            table.add(BehaviorFixture.blenderChild(generator: short, weight: 1), at: 0x200),
            table.add(BehaviorFixture.blenderChild(generator: long, weight: 1), at: 0x210)
        ]
        let root = table.add(
            BehaviorStateMachineFixture.syncedBlender(
                "locomotion", children: children, flags: BehaviorBlenderFlag.sync
            ),
            at: 0x300
        )
        let graph = BehaviorFixture.instance(
            root: root,
            table: table,
            clips: BehaviorClipTable(byName: [
                "short": BehaviorRampClip(duration: 1, boneIndex: 1),
                "long": BehaviorRampClip(duration: 2, boneIndex: 1)
            ])
        )
        for _ in 0 ..< 3 {
            graph.update(deltaTime: 0.1)
        }
        let shortState = try #require(graph.nodeStates[short])
        let longState = try #require(graph.nodeStates[long])
        #expect(abs(shortState.localTime - 0.2) < 1e-5)
        #expect(abs(longState.localTime - 0.4) < 1e-5)
    }

    /// Two synced copies of a one-second walk with a `FootLeft` mark: one footstep per
    /// loop, from the leader, not two.
    @Test func onlyTheLeaderOfASyncedBlenderRaisesItsFootsteps() throws {
        let walk = try BehaviorFixture.splineClip(annotations: [(time: 0.5, text: "FootLeft")])
        var table = BehaviorObjectTable()
        let slow = table.add(
            BehaviorFixture.clipGenerator("slow", animationName: "walk"),
            at: 0x100
        )
        let fast = table.add(
            BehaviorFixture.clipGenerator("fast", animationName: "walk"),
            at: 0x110
        )
        let children = [
            table.add(BehaviorFixture.blenderChild(generator: slow, weight: 1), at: 0x200),
            table.add(BehaviorFixture.blenderChild(generator: fast, weight: 1), at: 0x210)
        ]
        let root = table.add(
            BehaviorStateMachineFixture.syncedBlender(
                "locomotion", children: children, flags: BehaviorBlenderFlag.sync
            ),
            at: 0x300
        )
        let graph = BehaviorFixture.instance(
            root: root, table: table, clips: BehaviorClipTable(byName: ["walk": walk])
        )
        var footsteps = 0
        for _ in 0 ..< 30 {
            footsteps += graph.update(deltaTime: 0.1).unboundEvents.filter { $0 == "FootLeft" }
                .count
        }
        #expect(footsteps == 3)
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
