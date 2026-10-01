// One actor's values as a snapshot reads them. `ActorConditionState` and
// `PapyrusActorState` share this lookup rule: a primary's current value comes
// from the typed triple, every vanilla index from its stored entry or the record
// baseline, and an index outside the table answers nil.
// See docs/engine/actor-values.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// An observation of one actor's values that can answer for any actor value.
nonisolated public protocol ActorValueReadable {
    /// Current health, magicka and stamina.
    var current: ActorValues { get }
    /// Re-derived maximums for the three primaries.
    var maximums: ActorValues { get }
    /// Values this actor has moved off its baseline, resolved against it.
    var general: [Int32: ActorValueEntry] { get }
    /// Base values this actor's records author, keyed by vanilla index. Primaries are
    /// included, at their derived maximums.
    var generalBaseline: [Int32: Float] { get }
}

nonisolated extension ActorValueReadable {
    /// What `GetActorValue` reports for `index`, or nil for an index outside
    /// the vanilla table.
    public func value(at index: Int32) -> Float? {
        if let kind = ActorValueIdentity.kind(at: index) {
            return current[kind]
        }
        return entry(at: index)?.current
    }

    /// What `GetBaseActorValue` reports for `index`: the base value, which is
    /// what the records author until something writes one, and never a
    /// modifier.
    public func baseValue(at index: Int32) -> Float? {
        entry(at: index)?.base
    }

    /// `index`'s stored entry, or the unmodified entry its records author. Nil only
    /// for an index outside the table. A primary without a baseline falls back to
    /// `maximums`.
    public func entry(at index: Int32) -> ActorValueEntry? {
        guard let fallback = ActorValueIdentity.defaultValue(at: index) else { return nil }
        let baseline = if let kind = ActorValueIdentity.kind(at: index) {
            generalBaseline[index] ?? maximums[kind]
        } else {
            generalBaseline[index] ?? fallback
        }
        return general[index] ?? ActorValueEntry(base: baseline)
    }

    /// What `GetActorValuePercent` and `GetActorValuePercentage` report: the current
    /// value over its ceiling, clamped to 0 ... 1. A primary divides by its effective
    /// maximum, others by their base. A zero or negative denominator reads as 0.
    public func fraction(at index: Int32) -> Float? {
        guard let value = value(at: index) else { return nil }
        let ceiling: Float? = if let kind = ActorValueIdentity.kind(at: index) {
            maximums[kind]
        } else {
            baseValue(at: index)
        }
        guard let ceiling else { return nil }
        guard ceiling.isFinite, ceiling > 0, value.isFinite else { return 0 }
        return min(max(0, value / ceiling), 1)
    }
}
