// A rolling record of recent trigger transitions for World > World > Triggers. It
// subscribes to `CellStreamer.onTriggerTransition`, so it cannot reorder script
// events. It lives on the streamer, so it survives the panel being rebuilt.

import Foundation
import OpenSkyFormatsESM

/// One recorded transition, resolved as far as the streamer can resolve it.
///
/// `formID` is the load-order-relative FormID the plugin spelled, looked up
/// through `CellStreamer.referenceEntry(key:)`. It is nil when the authoring
/// cell has already been unloaded, which is exactly what happens for the leave
/// events `releaseTriggers(in:)` fires while a cell is going away.
nonisolated public struct TriggerTransitionRecord: Equatable, Sendable {
    public let event: TriggerTransitionEvent
    public let formID: FormID?

    /// One readout line: what happened, to which reference, and its FormID.
    public var line: String {
        let phase = event.phase == .enter ? "enter" : "leave"
        let form = formID.map { "0x\($0.description)" } ?? "unloaded"
        return "\(phase) \(event.reference.description) \(form)"
    }
}

/// Bounded, newest-last ring of `TriggerTransitionRecord`.
public final class TriggerEventLog {
    /// Records retained. The readout is a short tail a person reads at a
    /// glance, not an audit trail, and an unbounded log on a subscriber that
    /// fires on every volume edge would grow for the whole session.
    public static let capacity = 16

    public private(set) var records: [TriggerTransitionRecord] = []
    /// Transitions recorded since the last `clear()`, including the ones the
    /// ring has already dropped, so a full ring still reports honest totals.
    public private(set) var recordedCount = 0

    /// Appends one transition, dropping the oldest record past `capacity`.
    public func record(_ event: TriggerTransitionEvent, formID: FormID?) {
        records.append(TriggerTransitionRecord(event: event, formID: formID))
        if records.count > Self.capacity {
            records.removeFirst(records.count - Self.capacity)
        }
        recordedCount += 1
    }

    public func clear() {
        records.removeAll()
        recordedCount = 0
    }

    /// Readout lines, oldest first.
    public var lines: [String] {
        records.map(\.line)
    }

    public init() {}
}
