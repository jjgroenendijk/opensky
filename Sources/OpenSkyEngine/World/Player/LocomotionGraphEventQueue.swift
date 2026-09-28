// The hand-off between the graph events a fixed step fires and the frame-rate
// consumers that act on them (issues #352 and #195), split out of
// LocomotionBridge.swift for the strict-lint type-body cap.
//
// This is a queue rather than a readout, and the difference is the whole
// point. `LocomotionStatus.recentGraphEvents` keeps the newest names so the
// panel can show them and never consumes any: read it twice and you see the
// same names twice. A consumer that *acts* on an event — the footstep director
// playing a sound, the melee runtime opening a hit window — has to see each
// fired event exactly once, so it drains.
//
// Item 15.4 gave the queue a second consumer, and a drain-once queue cannot
// have two: whichever of them drained first would take the whole batch and the
// other would see an empty list. So the queue holds one cursor per registered
// consumer instead of one shared read head. Each consumer sees every name
// exactly once, in fire order, whatever order the consumers drain in and
// however many frames apart they do it.
//
// Cursors are positions in a monotonic sequence rather than indices into the
// storage, so trimming the front of the buffer cannot silently rewind or
// advance anybody. A name is dropped from storage once every consumer has read
// past it, which is the ordinary case and costs nothing.
//
// Steps run at 120 Hz and frames at whatever the display gives, so several
// steps' events accumulate between two drains. The queue is bounded and drops
// the oldest names past the bound: a consumer that stops draining entirely
// (audio switched off, a long build stall) must cost a fixed amount of memory
// and must not flush a minute of stale footsteps the moment it comes back. The
// bound is over the *undrained* names, so a slow consumer costs the fast one
// nothing but its own lost tail.

nonisolated final class LocomotionGraphEventQueue {
    /// How many undrained names the queue holds before it starts dropping the
    /// oldest. A frame at 60 Hz drives 2 fixed steps and a sprinting vanilla
    /// graph fires a handful of events per step, so 64 is several frames of
    /// headroom while staying a fixed, small bound.
    static let limit = 64

    /// One consumer's place in the stream.
    ///
    /// A reference type held by both the queue and its owner, so a consumer
    /// registered at wiring time keeps its position across every reset the
    /// bridge does. It carries no behavior and no identity beyond its cursor:
    /// there is deliberately no unregister, because every consumer here is
    /// wired once at setup and lives as long as the session does.
    final class Consumer {
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
    var consumerCount: Int {
        consumers.count
    }

    /// Registers a consumer, positioned at the head of the stream.
    ///
    /// A consumer registered mid-session starts empty rather than inheriting a
    /// backlog it has no context for — the same reasoning that makes a newly
    /// attached graph miss the transitions that happened before it existed.
    func addConsumer() -> Consumer {
        let consumer = Consumer(next: base + names.count)
        consumers.append(consumer)
        return consumer
    }

    /// Appends this step's fired events, oldest dropped first past the cap.
    /// Events the graph reports with no name carry nothing a consumer could
    /// match a footstep tag or a hit frame against, so they are not queued.
    func enqueue(_ events: [BehaviorEvent]) {
        guard !events.isEmpty else { return }
        names += events.compactMap(\.name)
        trim()
    }

    /// Hands `consumer` everything fired since its last drain and advances its
    /// cursor. Every other consumer's view is untouched.
    func drain(_ consumer: Consumer) -> [String] {
        let start = min(max(consumer.next - base, 0), names.count)
        consumer.next = base + names.count
        let drained = start < names.count ? Array(names[start...]) : []
        trim()
        return drained
    }

    /// Forgets everything queued, for every consumer. Called when the bridge
    /// resets, so a teleport does not play the footsteps of the place the
    /// player just left or land a hit the swing before it was cancelled.
    func clear() {
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
