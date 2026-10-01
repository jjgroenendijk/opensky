// Hands fixed-step graph events to frame-rate consumers. Each consumer has its own
// cursor in a monotonic sequence, so each sees every event once, in order, whenever it
// drains. Storage is bounded and drops the oldest undrained names, so a stalled consumer
// costs fixed memory and does not replay stale footsteps.

import OpenSkyBehavior

nonisolated public final class LocomotionGraphEventQueue {
    /// How many undrained names the queue holds before it starts dropping the
    /// oldest. A frame at 60 Hz drives 2 fixed steps and a sprinting vanilla
    /// graph fires a handful of events per step, so 64 is several frames of
    /// headroom while staying a fixed, small bound.
    public static let limit = 64

    /// One consumer's place in the stream, shared by the queue and its owner so it
    /// survives resets. There is no unregister: consumers live for the whole session.
    public final class Consumer {
        /// Sequence number of the next name this consumer has not seen.
        fileprivate var next: Int

        fileprivate init(next: Int) {
            self.next = next
        }
    }

    /// Undrained names, oldest first.
    private var names: [String] = []
    /// Sequence number of `names[0]`. Rises as the front is trimmed.
    private var base = 0
    private var consumers: [Consumer] = []

    /// How many consumers are registered. Tests assert on it; the engine does
    /// not branch on it.
    public var consumerCount: Int {
        consumers.count
    }

    /// Registers a consumer, positioned at the head of the stream.
    ///
    /// A consumer registered mid-session starts empty rather than inheriting a
    /// backlog it has no context for — the same reasoning that makes a newly
    /// attached graph miss the transitions that happened before it existed.
    public func addConsumer() -> Consumer {
        let consumer = Consumer(next: base + names.count)
        consumers.append(consumer)
        return consumer
    }

    /// Appends this step's fired events, oldest dropped first past the cap.
    /// Events the graph reports with no name carry nothing a consumer could
    /// match a footstep tag or a hit frame against, so they are not queued.
    public func enqueue(_ events: [BehaviorEvent]) {
        guard !events.isEmpty else { return }
        names += events.compactMap(\.name)
        trim()
    }

    /// Hands `consumer` everything fired since its last drain and advances its
    /// cursor. Every other consumer's view is untouched.
    public func drain(_ consumer: Consumer) -> [String] {
        let start = min(max(consumer.next - base, 0), names.count)
        consumer.next = base + names.count
        let drained = start < names.count ? Array(names[start...]) : []
        trim()
        return drained
    }

    /// Forgets everything queued, for every consumer. Called when the bridge
    /// resets, so a teleport does not play the footsteps of the place the
    /// player just left or land a hit the swing before it was cancelled.
    public func clear() {
        base += names.count
        names.removeAll(keepingCapacity: true)
        for consumer in consumers {
            consumer.next = base
        }
    }

    /// Drops the names every consumer has read past, then enforces the cap on
    /// what is left.
    ///
    /// With no consumer registered the whole buffer is dropped: nothing can
    /// ever read it, and keeping it would make the memory bound depend on how
    /// long the app runs before anything subscribes.
    private func trim() {
        let head = base + names.count
        let slowest = consumers.map(\.next).min() ?? head
        var drop = min(max(slowest - base, 0), names.count)
        let overflow = names.count - drop - Self.limit
        if overflow > 0 {
            drop += overflow
        }
        guard drop > 0 else { return }
        names.removeFirst(drop)
        base += drop
        for consumer in consumers where consumer.next < base {
            consumer.next = base
        }
    }
}
