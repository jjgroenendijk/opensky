// The hand-off between the graph events a fixed step fires and the frame-rate
// consumer that acts on them (issue #352), split out of LocomotionBridge.swift
// for the strict-lint type-body cap.
//
// This is a queue rather than a readout, and the difference is the whole
// point. `LocomotionStatus.recentGraphEvents` keeps the newest names so the
// panel can show them and never consumes any: read it twice and you see the
// same names twice. A consumer that *acts* on an event — the footstep director
// playing a sound — has to see each fired event exactly once, so it drains.
//
// Steps run at 120 Hz and frames at whatever the display gives, so several
// steps' events accumulate between two drains. The queue is bounded and drops
// the oldest names past the bound: a consumer that stops draining entirely
// (audio switched off, a long build stall) must cost a fixed amount of memory
// and must not flush a minute of stale footsteps the moment it comes back.

nonisolated final class LocomotionGraphEventQueue {
    /// How many undrained names the queue holds before it starts dropping the
    /// oldest. A frame at 60 Hz drives 2 fixed steps and a sprinting vanilla
    /// graph fires a handful of events per step, so 64 is several frames of
    /// headroom while staying a fixed, small bound.
    static let limit = 64

    private var names: [String] = []

    /// Appends this step's fired events, oldest dropped first past the cap.
    /// Events the graph reports with no name carry nothing a consumer could
    /// match a footstep tag against, so they are not queued.
    func enqueue(_ events: [BehaviorEvent]) {
        guard !events.isEmpty else { return }
        names += events.compactMap(\.name)
        let overflow = names.count - Self.limit
        if overflow > 0 {
            names.removeFirst(overflow)
        }
    }

    /// Hands over everything queued since the last call and clears the queue.
    func drain() -> [String] {
        defer { names.removeAll(keepingCapacity: true) }
        return names
    }

    /// Forgets everything queued. Called when the bridge resets, so a teleport
    /// does not play the footsteps of the place the player just left.
    func clear() {
        names.removeAll(keepingCapacity: true)
    }
}
