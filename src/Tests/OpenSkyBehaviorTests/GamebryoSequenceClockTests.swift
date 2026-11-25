// A played NIF sequence raises its text keys in its graph, so a hand effect leaves its
// intro state when the `mIntro` sequence passes `end`.

import Foundation
import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
import Testing

struct GamebryoSequenceClockTests {
    private static let intro = GamebryoSequenceTiming(
        duration: 0.05, loops: false,
        keys: [.init(time: 0.05, name: "end"), .init(time: 0, name: "start")]
    )
    private static let idle = GamebryoSequenceTiming(
        duration: 0.1, loops: true,
        keys: [.init(time: 0, name: "start"), .init(time: 0.1, name: "end")]
    )

    @Test func aClampedSequencePassesEachKeyOnce() {
        var clock = GamebryoSequenceClock(timings: ["mIntro": Self.intro])

        let first = clock.advance(playing: ["MINTRO"], by: 0.03)
        let second = clock.advance(playing: ["mIntro"], by: 0.03)
        let third = clock.advance(playing: ["mIntro"], by: 0.03)
        let fourth = clock.advance(playing: ["mIntro"], by: 0.03)

        #expect(first == ["start"], "a sequence just reached stands at 0")
        #expect(second.isEmpty)
        #expect(third == ["end"])
        #expect(fourth.isEmpty, "a clamped sequence holds its end")
    }

    @Test func aLoopingSequencePassesItsKeysOnEachLap() {
        var clock = GamebryoSequenceClock(timings: ["mIdle": Self.idle])

        _ = clock.advance(playing: ["mIdle"], by: 0.06)
        _ = clock.advance(playing: ["mIdle"], by: 0.06)
        let lap = clock.advance(playing: ["mIdle"], by: 0.06)

        #expect(lap == ["end", "start"], "the lap ends, then the next one starts")
    }

    @Test func aSequenceTheGraphLeftStartsAgain() {
        var clock = GamebryoSequenceClock(timings: ["mIntro": Self.intro, "mIdle": Self.idle])
        _ = clock.advance(playing: ["mIntro"], by: 0.03)
        _ = clock.advance(playing: ["mIdle"], by: 0.03)

        let back = clock.advance(playing: ["mIntro", "mUnknown"], by: 0.03)

        #expect(back == ["start"])
    }

    @Test func anIntroSequenceEndLeadsTheGraphToItsNextState() {
        var table = BehaviorObjectTable()
        let introSequence = table.add(
            BGSGamebryoSequenceGenerator(
                node: BehaviorFixture.nodeHeader("mIntroSequence"),
                sequence: "mIntro", blendModeFunction: 0, percent: 1, unresolved: []
            ),
            at: 0x100
        )
        let idleSequence = table.add(
            BGSGamebryoSequenceGenerator(
                node: BehaviorFixture.nodeHeader("mIdleSequence"),
                sequence: "mIdle", blendModeFunction: 0, percent: 1, unresolved: []
            ),
            at: 0x110
        )
        let toIdle = table.add(
            BehaviorStateMachineFixture.transitions([.init(eventId: 0, toStateId: 1)]),
            at: 0x200
        )
        let introState = table.add(
            BehaviorStateMachineFixture.stateInfo(
                .init(
                    stateId: 0,
                    name: "mIntroState",
                    generator: introSequence,
                    transitions: toIdle
                )
            ),
            at: 0x300
        )
        let idleState = table.add(
            BehaviorStateMachineFixture.stateInfo(
                .init(stateId: 1, name: "mIdleState", generator: idleSequence)
            ),
            at: 0x310
        )
        let root = table.add(
            BehaviorStateMachineFixture.machine("hand", states: [introState, idleState]),
            at: 0x400
        )
        let graph = BehaviorFixture.instance(
            root: root, table: table, data: BehaviorFixture.graphData(events: ["end"])
        )
        graph.sequenceClock = GamebryoSequenceClock(timings: ["mIntro": Self.intro])

        for _ in 0 ..< 5 {
            graph.update(deltaTime: 1 / 60)
        }

        #expect(graph.activeStates.last?.stateName == "mIdleState")
        #expect(graph.gamebryoSequences == ["mIdle"])
    }

    @Test func aReferencedGraphsSequenceCountsAsItsParents() {
        var childTable = BehaviorObjectTable()
        let charge = childTable.add(
            BGSGamebryoSequenceGenerator(
                node: BehaviorFixture.nodeHeader("mChargeSequence"),
                sequence: "mCharge", blendModeFunction: 0, percent: 1, unresolved: []
            ),
            at: 0x100
        )
        let child = BehaviorFixture.instance(root: charge, table: childTable)
        var table = BehaviorObjectTable()
        let root = table.add(
            HKBBehaviorReferenceGenerator(
                node: BehaviorFixture.nodeHeader("reference"),
                behaviorName: "child.hkx", unresolved: []
            ),
            at: 0x100
        )
        let parent = BehaviorFixture.instance(root: root, table: table)
        parent.references = BehaviorReferenceTable(graphs: ["child.hkx": child])

        parent.update(deltaTime: 1 / 60)

        #expect(parent.gamebryoSequences == ["mCharge"])
    }
}
