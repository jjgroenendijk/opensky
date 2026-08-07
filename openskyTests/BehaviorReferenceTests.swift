// `hkbBehaviorReferenceGenerator` event crossing (issue #189, fixed for issues
// #385 and #394).
//
// Skyrim's player graph is a shell whose locomotion lives in a referenced
// behavior file, so an event that crosses the seam wrong breaks every feature
// downstream of it. These run over synthetic graphs built in code — nothing
// here is extracted from a game file (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

/// A `BehaviorReferenceSource` backed by instances the test already built.
private struct BehaviorReferenceTable: BehaviorReferenceSource {
    let graphs: [String: BehaviorGraphInstance]

    func behavior(
        named name: String,
        skeleton _: BehaviorSkeleton,
        clips _: any BehaviorClipSource
    ) -> BehaviorGraphInstance? {
        graphs[BehaviorGraphInstance.referenceKey(name)]
    }
}

struct BehaviorReferenceTests {
    /// Events cross the seam once each way and then stop.
    ///
    /// The parent raises `poke`; the child's machine transitions on it and its
    /// destination state raises `pong` on entry; the parent sees `pong` on a
    /// later update. Both counts have to be exactly one.
    ///
    /// They were not. The parent used to raise the child's *active* set back on
    /// itself, and that set already held everything the parent had just pushed
    /// down, so every crossing event bounced between the two graphs once per
    /// update forever. The vanilla player graph re-fired `moveStart` and
    /// `IdleStop` on all 120 steps of a second, which is what saturated the
    /// bounded queue in `LocomotionGraphEventQueue` and pushed the real
    /// footstep tags out of it (issues #385, #394).
    @Test func anEventCrossesTheReferenceSeamOnceInEachDirection() {
        let child = Self.child()
        let parent = Self.parent(references: BehaviorReferenceTable(
            graphs: ["child.hkx": child]
        ))
        #expect(parent.raiseEvent(named: "poke"))

        var counts: [String: Int] = [:]
        for _ in 0 ..< 20 {
            for event in parent.update(deltaTime: 1 / 30).firedEvents {
                counts[event.name ?? "", default: 0] += 1
            }
        }
        #expect(counts["poke"] == 1)
        #expect(counts["pong"] == 1, "the child's own event echoed back down and up again")
    }

    /// A reference the source cannot answer leaves the parent's own events
    /// alone rather than dropping them, so the unresolved case stays the tallied
    /// no-op it was.
    @Test func anUnresolvedReferenceStillDeliversTheParentsOwnEvents() {
        let parent = Self.parent(references: BehaviorReferenceTable(graphs: [:]))
        #expect(parent.raiseEvent(named: "poke"))

        #expect(parent.update(deltaTime: 1 / 30).firedEvents.map(\.name) == ["poke"])
        #expect(parent.update(deltaTime: 1 / 30).firedEvents.isEmpty)
        #expect(parent.tally.featureGaps["unresolvedBehaviorReference"] ?? 0 > 0)
    }

    // MARK: - Graphs

    private static let events = ["poke", "pong"]

    /// A graph whose whole content is one reference to `child.hkx`.
    private static func parent(
        references: some BehaviorReferenceSource
    ) -> BehaviorGraphInstance {
        var table = BehaviorObjectTable()
        let root = table.add(
            HKBBehaviorReferenceGenerator(
                node: BehaviorFixture.nodeHeader("reference"),
                behaviorName: "child.hkx",
                unresolved: []
            ),
            at: 0x100
        )
        let graph = BehaviorFixture.instance(
            root: root, table: table, data: BehaviorFixture.graphData(events: events)
        )
        graph.references = references
        return graph
    }

    /// A two-state machine that moves to `Answered` on `poke` and raises `pong`
    /// as it enters.
    private static func child() -> BehaviorGraphInstance {
        var table = BehaviorObjectTable()
        let transitions = table.add(
            BehaviorStateMachineFixture.transitions([
                BehaviorTransitionSpec(eventId: 0, toStateId: 1)
            ]),
            at: 0x200
        )
        let notify = table.add(BehaviorStateMachineFixture.notifyEvents([1]), at: 0x210)
        let waiting = table.add(
            BehaviorStateMachineFixture.stateInfo(
                BehaviorStateSpec(stateId: 0, name: "Waiting", transitions: transitions)
            ),
            at: 0x220
        )
        let answered = table.add(
            BehaviorStateMachineFixture.stateInfo(
                BehaviorStateSpec(stateId: 1, name: "Answered", enterNotifyEvents: notify)
            ),
            at: 0x230
        )
        let root = table.add(
            BehaviorStateMachineFixture.machine("child", states: [waiting, answered]),
            at: 0x240
        )
        return BehaviorFixture.instance(
            root: root, table: table, data: BehaviorFixture.graphData(events: events)
        )
    }
}
