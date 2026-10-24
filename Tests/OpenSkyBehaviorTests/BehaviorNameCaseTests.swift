// Graph events and variables match by name without case, as in the game.

import OpenSkyBehavior
import OpenSkyEngineTesting
import OpenSkyFormatsAnimation
import Testing

struct BehaviorNameCaseTests {
    /// The vanilla trap scripts raise `loop` and `reset` on a blade graph that declares
    /// `Loop` and `Reset`, and the blade swings in the game.
    @Test func eventsMatchWithoutCase() {
        var queue = BehaviorEventQueue(data: BehaviorFixture.graphData(events: ["Loop", "Reset"]))
        #expect(queue.index(of: "loop") == 0)
        #expect(queue.index(of: "RESET") == 1)
        let raised = queue.raise(named: "loop")
        #expect(raised)
        #expect(queue.pending.map(\.id) == [0])
    }

    @Test func variablesMatchWithoutCase() {
        let store = BehaviorVariableStore(data: BehaviorFixture.graphData(variables: [
            BehaviorVariableSpec("bReady", .bool, 1)
        ]))
        #expect(store.index(of: "BREADY") == 0)
    }
}
