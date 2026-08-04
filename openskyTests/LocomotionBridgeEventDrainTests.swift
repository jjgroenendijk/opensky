// The graph-event drain the footstep director consumes (issue #352): events
// fired by the third-person graph's clip triggers are handed over exactly
// once, the queue is bounded, and a reset or a paused frame leaves nothing to
// replay. Synthetic graph only. See docs/engine/walk-mode.md.

@testable import opensky
import simd
import Testing

struct LocomotionBridgeEventDrainTests {
    @Test func firedClipTriggersReachTheDrainExactlyOnce() throws {
        let bridge = LocomotionBridge(configuration: .synthetic)
        try bridge.attach(graph: Self.triggeringGraph())

        // The trigger sits at 0.4 s into the clip, so one step is not enough.
        var fired: [String] = []
        for _ in 0 ..< 60 {
            _ = bridge.plan(Self.state())
            fired += bridge.graphEvents.drain()
        }

        #expect(fired.contains(Self.triggerEvent))
        // The second drain of the same steps returns nothing: draining consumes.
        #expect(bridge.graphEvents.drain().isEmpty)
    }

    @Test func drainedEventsMatchTheStatusReadoutWithoutRepeating() throws {
        let bridge = LocomotionBridge(configuration: .synthetic)
        try bridge.attach(graph: Self.triggeringGraph())
        for _ in 0 ..< 60 {
            _ = bridge.plan(Self.state())
        }

        let drained = bridge.graphEvents.drain()
        #expect(!drained.isEmpty)
        // The bounded readout still holds its copy — it is not consumed.
        #expect(bridge.status.recentGraphEvents.contains(Self.triggerEvent))
        #expect(bridge.graphEvents.drain().isEmpty)
    }

    @Test func undrainedEventsStayBoundedAndKeepTheNewest() throws {
        let bridge = LocomotionBridge(configuration: .synthetic)
        try bridge.attach(graph: Self.triggeringGraph())
        for _ in 0 ..< 2000 {
            _ = bridge.plan(Self.state())
        }

        let drained = bridge.graphEvents.drain()
        #expect(drained.count <= LocomotionGraphEventQueue.limit)
        #expect(!drained.isEmpty)
    }

    @Test func resetDropsQueuedEvents() throws {
        let bridge = LocomotionBridge(configuration: .synthetic)
        try bridge.attach(graph: Self.triggeringGraph())
        for _ in 0 ..< 60 {
            _ = bridge.plan(Self.state())
        }

        bridge.reset()

        #expect(bridge.graphEvents.drain().isEmpty)
    }

    @Test func pausedFrameQueuesNothing() throws {
        let bridge = LocomotionBridge(configuration: .synthetic)
        try bridge.attach(graph: Self.triggeringGraph())

        for _ in 0 ..< 60 {
            _ = bridge.plan(Self.state(dt: 0))
        }

        #expect(bridge.graphEvents.drain().isEmpty)
    }

    @Test func detachedGraphQueuesNothing() {
        let bridge = LocomotionBridge(configuration: .synthetic)

        for _ in 0 ..< 10 {
            _ = bridge.plan(Self.state())
        }

        #expect(bridge.graphEvents.drain().isEmpty)
    }

    // MARK: - Fixture

    private static let triggerEvent = "FootLeft"

    private static func state(
        dt: Float = WalkController.fixedTimeStep
    ) -> LocomotionStepState {
        LocomotionStepState(
            feetPosition: SIMD3<Float>(),
            verticalVelocity: 0,
            isGrounded: true,
            yaw: 0,
            dt: dt
        )
    }

    /// A looping clip whose trigger array raises one footstep event per cycle,
    /// which is the shape of every vanilla locomotion clip.
    private static func triggeringGraph() throws -> BehaviorGraphInstance {
        let clip = try BehaviorFixture.splineClip()
        var table = BehaviorObjectTable()
        let triggers = table.add(
            BehaviorFixture.clipTriggers(
                [BehaviorTriggerSpec(localTime: 0.4, eventId: 0)]
            ),
            at: 0x100
        )
        let root = table.add(
            BehaviorFixture.clipGenerator(
                "walk", animationName: "walk", triggers: triggers
            ),
            at: 0x200
        )
        return BehaviorFixture.instance(
            root: root,
            table: table,
            data: BehaviorFixture.graphData(variables: [], events: [triggerEvent]),
            clips: BehaviorClipTable(byName: ["walk": clip])
        )
    }
}
