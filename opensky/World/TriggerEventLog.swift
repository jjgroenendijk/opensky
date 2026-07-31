// Rolling record of the most recent trigger-volume transitions (issue #173),
// so `World > World > Triggers` can show what fired without a CLI command.
//
// The log is a *subscriber* to `CellStreamer.onTriggerTransition`, registered
// through the same `CallbackFanOut` the Papyrus bridge uses, and never part of
// the per-frame dispatch path: adding it costs one more closure call on an edge
// event and cannot displace or reorder a script event. It lives on the streamer
// rather than on the panel because a panel is built lazily on first reveal and
// rebuilt on a Settings reload, and a log that restarted empty every time the
// user opened the destination would be useless for verification.

import Foundation

/// One recorded transition, resolved as far as the streamer can resolve it.
///
/// `formID` is the load-order-relative FormID the plugin spelled, looked up
/// through `CellStreamer.referenceEntry(key:)`. It is nil when the authoring
/// cell has already been unloaded, which is exactly what happens for the leave
/// events `releaseTriggers(in:)` fires while a cell is going away.
nonisolated struct TriggerTransitionRecord: Equatable, Sendable {
    let event: TriggerTransitionEvent
    let formID: FormID?

    /// One readout line: what happened, to which reference, and its FormID.
    var line: String {
        let phase = event.phase == .enter ? "enter" : "leave"
        let form = formID.map { "0x\($0.description)" } ?? "unloaded"
        return "\(phase) \(event.reference.description) \(form)"
    }
}

/// Bounded, newest-last ring of `TriggerTransitionRecord`.
final class TriggerEventLog {
    /// Records retained. The readout is a short tail a person reads at a
    /// glance, not an audit trail, and an unbounded log on a subscriber that
    /// fires on every volume edge would grow for the whole session.
    static let capacity = 16

    private(set) var records: [TriggerTransitionRecord] = []
    /// Transitions recorded since the last `clear()`, including the ones the
    /// ring has already dropped, so a full ring still reports honest totals.
    private(set) var recordedCount = 0

    /// Appends one transition, dropping the oldest record past `capacity`.
    func record(_ event: TriggerTransitionEvent, formID: FormID?) {
        records.append(TriggerTransitionRecord(event: event, formID: formID))
        if records.count > Self.capacity {
            records.removeFirst(records.count - Self.capacity)
        }
        recordedCount += 1
    }

    func clear() {
        records.removeAll()
        recordedCount = 0
    }

    /// Readout lines, oldest first.
    var lines: [String] {
        records.map(\.line)
    }
}
