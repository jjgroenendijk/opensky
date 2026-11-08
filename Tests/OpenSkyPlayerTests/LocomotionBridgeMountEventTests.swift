// The mount coordinator's own cursor into the bridge's graph events.

@testable import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyPlayer
import Testing

struct LocomotionBridgeMountEventTests {
    /// Each drain hands over only the events fired since the last one.
    @Test
    func drainingMountEventsHandsEachEventOverOnce() {
        var table = BehaviorObjectTable()
        let root = table.add(
            BehaviorFixture.clipGenerator("idle", animationName: "idle"), at: 0x10
        )
        let graph = BehaviorFixture.instance(
            root: root, table: table, data: BehaviorFixture.graphData()
        )
        let bridge = LocomotionBridge(configuration: .synthetic, graph: graph)
        bridge.graphEvents.enqueue([], unbound: ["HorseEnter"])
        #expect(bridge.drainMountEvents() == ["HorseEnter"])
        #expect(bridge.drainMountEvents().isEmpty)
    }
}
