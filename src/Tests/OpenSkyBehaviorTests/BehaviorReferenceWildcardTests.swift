// A global wildcard in a referenced behaviour file moves the machines of the file
// that refers to it. The cart exit depends on it: the event that binds a prisoner's
// arms lives in the locomotion file and takes the top machine out of the cart state.
// See docs/engine/behavior-state-machines.md#global-wildcards.

import Foundation
@testable import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
import Testing

struct BehaviorReferenceWildcardTests {
    private static let step: Float = 1 / 30
    private static let global = BehaviorTransitionFlag.globalWildcard
        | BehaviorTransitionFlag.localWildcard | BehaviorTransitionFlag.disableCondition
    private static let local = BehaviorTransitionFlag.localWildcard
        | BehaviorTransitionFlag.disableCondition

    @Test func aGlobalWildcardInAReferencedFileMovesTheMachineAboveIt() {
        let child = Self.child(wildcardFlags: Self.global)
        let parent = Self.parent(child: child)
        parent.update(deltaTime: Self.step)
        #expect(parent.activeStates.map(\.stateName) == ["Seat"])

        #expect(parent.raiseEvent(named: "bind"))
        var fired: [String] = []
        for _ in 0 ..< 3 {
            fired += parent.update(deltaTime: Self.step).firedEvents.compactMap(\.name)
        }
        #expect(parent.activeStates.map(\.stateName) == ["Walk", "Bound"])
        #expect(fired.contains("left"), "the seat state sent no exit event: \(fired)")
    }

    @Test func aLocalWildcardInAReferencedFileLeavesTheMachineAboveItAlone() {
        let parent = Self.parent(child: Self.child(wildcardFlags: Self.local))
        parent.update(deltaTime: Self.step)
        parent.raiseEvent(named: "bind")
        for _ in 0 ..< 3 {
            parent.update(deltaTime: Self.step)
        }
        #expect(parent.activeStates.map(\.stateName) == ["Seat"])
    }

    @Test func graphsOverOneFileShareTheirWildcardRoutes() {
        let caches = BehaviorFileCaches()
        let first = Self.parent(child: Self.child(wildcardFlags: Self.global), caches: caches)
        let second = Self.parent(child: Self.child(wildcardFlags: Self.global), caches: caches)
        for graph in [first, second] {
            graph.update(deltaTime: Self.step)
            graph.raiseEvent(named: "bind")
            for _ in 0 ..< 3 {
                graph.update(deltaTime: Self.step)
            }
            #expect(graph.activeStates.map(\.stateName) == ["Walk", "Bound"])
        }
        #expect(caches.globalWildcardTables.count == 1)
        let routes = caches.globalWildcardTables.values.first?.routes ?? []
        #expect(routes.map(\.holderPath) == [["child.hkx"]])
    }

    // MARK: - Graphs

    /// A top machine that starts in `Seat` and holds the reference in `Walk`. It has
    /// no transition of its own, so only the child's wildcard can move it.
    private static func parent(
        child: BehaviorGraphInstance,
        caches: BehaviorFileCaches? = nil
    ) -> BehaviorGraphInstance {
        var table = BehaviorObjectTable()
        let reference = table.add(
            HKBBehaviorReferenceGenerator(
                node: BehaviorFixture.nodeHeader("reference"),
                behaviorName: "child.hkx",
                unresolved: []
            ),
            at: 0x100
        )
        let exit = table.add(BehaviorStateMachineFixture.notifyEvents([1]), at: 0x110)
        let seat = table.add(
            BehaviorStateMachineFixture.stateInfo(
                BehaviorStateSpec(stateId: 0, name: "Seat", exitNotifyEvents: exit)
            ),
            at: 0x120
        )
        let walk = table.add(
            BehaviorStateMachineFixture.stateInfo(
                BehaviorStateSpec(stateId: 1, name: "Walk", generator: reference)
            ),
            at: 0x130
        )
        let root = table.add(
            BehaviorStateMachineFixture.machine("top", states: [seat, walk]), at: 0x140
        )
        let graph = BehaviorGraphInstance(
            root: root,
            data: BehaviorFixture.graphData(events: ["bind", "left"]),
            source: CachedTable(table: table, fileCaches: caches),
            skeleton: BehaviorFixture.skeleton(),
            clips: EmptyBehaviorClipSource()
        )
        graph.references = BehaviorReferenceTable(graphs: ["child.hkx": child])
        return graph
    }

    /// A machine with a wildcard on `bind` to `Bound`. Its event ids differ from the
    /// parent's, so the two files can only match the event by name.
    private static func child(wildcardFlags: Int) -> BehaviorGraphInstance {
        var table = BehaviorObjectTable()
        let wildcards = table.add(
            BehaviorStateMachineFixture.transitions([
                BehaviorTransitionSpec(eventId: 1, toStateId: 1, flags: wildcardFlags)
            ]),
            at: 0x200
        )
        let free = table.add(
            BehaviorStateMachineFixture.stateInfo(BehaviorStateSpec(stateId: 0, name: "Free")),
            at: 0x210
        )
        let bound = table.add(
            BehaviorStateMachineFixture.stateInfo(BehaviorStateSpec(stateId: 1, name: "Bound")),
            at: 0x220
        )
        let root = table.add(
            BehaviorStateMachineFixture.machine(
                "arms", states: [free, bound], wildcardTransitions: wildcards
            ),
            at: 0x230
        )
        return BehaviorFixture.instance(
            root: root, table: table, data: BehaviorFixture.graphData(events: ["other", "bind"])
        )
    }
}

/// A fixture table that shares `fileCaches` the way one decoded file does.
private struct CachedTable: BehaviorObjectSource {
    let table: BehaviorObjectTable
    let fileCaches: BehaviorFileCaches?

    func object(at target: HKXPointerTarget) -> (any HKBClass)? {
        table.object(at: target)
    }

    func className(at target: HKXPointerTarget) -> String? {
        table.className(at: target)
    }
}
