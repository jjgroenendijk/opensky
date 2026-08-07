// The multi-consumer graph-event queue (issue #195, roadmap item 15.4, scope
// point 1): the footstep director and the melee runtime both read the same
// fired-event stream, and each sees every event exactly once.
//
// The acceptance the issue names is the first test here. The rest pin the
// properties that make the fan-out safe to leave running for a session: the
// bound is over undrained names so a stopped consumer costs the other nothing
// but its own tail, a reset empties every cursor at once, and a consumer
// registered later starts at the head rather than inheriting a backlog.
//
// Synthetic names throughout; nothing here needs a graph.

@testable import opensky
import Testing

struct LocomotionGraphEventFanOutTests {
    @Test func twoConsumersEachSeeOneEventExactlyOnce() {
        let queue = LocomotionGraphEventQueue()
        let footsteps = queue.addConsumer()
        let melee = queue.addConsumer()

        queue.enqueue([Self.event("HitFrame")])

        #expect(queue.drain(footsteps) == ["HitFrame"])
        #expect(queue.drain(melee) == ["HitFrame"])
        // Exactly once each: a second drain by either sees nothing.
        #expect(queue.drain(footsteps).isEmpty)
        #expect(queue.drain(melee).isEmpty)
    }

    @Test func consumersDrainIndependentlyAndInFireOrder() {
        let queue = LocomotionGraphEventQueue()
        let fast = queue.addConsumer()
        let slow = queue.addConsumer()

        queue.enqueue([Self.event("FootLeft")])
        #expect(queue.drain(fast) == ["FootLeft"])
        queue.enqueue([Self.event("attackStart"), Self.event("HitFrame")])

        // The fast consumer sees only what it has not seen; the slow one
        // catches up on the whole stream, in fire order.
        #expect(queue.drain(fast) == ["attackStart", "HitFrame"])
        #expect(queue.drain(slow) == ["FootLeft", "attackStart", "HitFrame"])
    }

    @Test func aStoppedConsumerLosesItsOwnTailAndNobodyElsesEvents() {
        let queue = LocomotionGraphEventQueue()
        let active = queue.addConsumer()
        let stopped = queue.addConsumer()

        for index in 0 ..< (LocomotionGraphEventQueue.limit * 4) {
            queue.enqueue([Self.event("event\(index)")])
            #expect(queue.drain(active).count == 1)
        }

        let backlog = queue.drain(stopped)
        #expect(backlog.count == LocomotionGraphEventQueue.limit)
        // The newest are what survived, which is what stops a consumer coming
        // back from flushing a minute of stale events.
        #expect(backlog.last == "event\(LocomotionGraphEventQueue.limit * 4 - 1)")
    }

    @Test func clearEmptiesEveryCursorAtOnce() {
        let queue = LocomotionGraphEventQueue()
        let footsteps = queue.addConsumer()
        let melee = queue.addConsumer()
        queue.enqueue([Self.event("FootLeft"), Self.event("HitFrame")])

        queue.clear()

        #expect(queue.drain(footsteps).isEmpty)
        #expect(queue.drain(melee).isEmpty)
    }

    @Test func aConsumerRegisteredLaterStartsAtTheHead() {
        let queue = LocomotionGraphEventQueue()
        let first = queue.addConsumer()
        queue.enqueue([Self.event("FootLeft")])

        let second = queue.addConsumer()
        queue.enqueue([Self.event("HitFrame")])

        #expect(queue.drain(second) == ["HitFrame"])
        #expect(queue.drain(first) == ["FootLeft", "HitFrame"])
    }

    @Test func unnamedEventsAreNotQueued() {
        let queue = LocomotionGraphEventQueue()
        let consumer = queue.addConsumer()

        queue.enqueue([BehaviorEvent(id: 7, name: nil), Self.event("HitFrame")])

        #expect(queue.drain(consumer) == ["HitFrame"])
    }

    /// Footsteps, melee, archery (issue #196) and ragdoll (issue #197) —
    /// registered eagerly at construction, because the queue drops what no
    /// registered cursor can ever read and a cursor created on first drain
    /// would find it empty.
    @Test func theBridgeRegistersEveryCursorAtConstruction() {
        let bridge = LocomotionBridge(configuration: .synthetic)
        #expect(bridge.graphEvents.consumerCount == 4)
    }

    /// The fourth consumer must not displace the first three either.
    @Test func theRagdollCursorSeesTheSameStreamAsTheOtherThree() {
        let bridge = LocomotionBridge(configuration: .synthetic)
        bridge.graphEvents.enqueue([
            Self.event(RagdollGraphNames.addRagdollToWorld), Self.event("HitFrame")
        ])

        let ragdoll = bridge.graphEvents.drain(bridge.ragdollEventConsumer)
        let melee = bridge.graphEvents.drain(bridge.meleeEventConsumer)
        #expect(ragdoll == [RagdollGraphNames.addRagdollToWorld, "HitFrame"])
        #expect(melee == ragdoll)
    }

    /// The third consumer must not displace either of the first two: each sees
    /// every name exactly once, whatever order they drain in.
    @Test func theArcheryCursorSeesTheSameStreamAsTheOtherTwo() {
        let bridge = LocomotionBridge(configuration: .synthetic)
        bridge.graphEvents.enqueue([Self.event("arrowRelease"), Self.event("HitFrame")])

        let archery = bridge.graphEvents.drain(bridge.archeryEventConsumer)
        let melee = bridge.graphEvents.drain(bridge.meleeEventConsumer)
        let footsteps = bridge.graphEvents.drain(bridge.footstepEventConsumer)

        #expect(archery == ["arrowRelease", "HitFrame"])
        #expect(melee == archery)
        #expect(footsteps == archery)
    }

    private static func event(_ name: String) -> BehaviorEvent {
        BehaviorEvent(id: abs(name.hashValue % 1000), name: name)
    }
}
