// One actor's values as a *snapshot* reads them (issue #468, roadmap item
// 19.5).
//
// Two surfaces take an observation of an actor rather than reading the runtime
// live — `ActorConditionState` for a condition evaluation and
// `PapyrusActorState` for a native call — and both now have to answer for the
// whole 164-entry table rather than for three typed fields. The lookup rule is
// identical on both sides, so it is written once here instead of twice with two
// chances to disagree about what an untouched resistance reads.
//
// The rule, in one sentence: a primary's *current* value answers from the typed
// triple, every vanilla index answers its base and modifiers from the stored
// entry when there is one and from the record baseline when there is not, and
// an index outside the table answers nil so the caller can count it.
//
// Documented in docs/engine/actor-values.md.

import Foundation

/// An observation of one actor's values that can answer for any actor value.
nonisolated protocol ActorValueReadable {
    /// Current health, magicka and stamina.
    var current: ActorValues { get }
    /// Re-derived maximums for the three primaries.
    var maximums: ActorValues { get }
    /// Values this actor has moved off its baseline, resolved against it.
    var general: [Int32: ActorValueEntry] { get }
    /// Base values this actor's records author, keyed by vanilla index. The
    /// primaries are in here too since item 20.3, at their derived maximums.
    var generalBaseline: [Int32: Float] { get }
    /// Whether this actor is the player, which is the only thing the resistance
    /// cap depends on.
    var isPlayer: Bool { get }
}

nonisolated extension ActorValueReadable {
    /// What `GetActorValue` reports for `index`, or nil for an index outside
    /// the vanilla table.
    func value(at index: Int32) -> Float? {
        if let kind = ActorValueIdentity.kind(at: index) {
            return current[kind]
        }
        return entry(at: index)?.current
    }

    /// What `GetBaseActorValue` reports for `index`: the base value, which is
    /// what the records author until something writes one, and never a
    /// modifier.
    func baseValue(at index: Int32) -> Float? {
        entry(at: index)?.base
    }

    /// `index`'s stored entry, or the unmodified entry its records author. Nil
    /// only for an index outside the table.
    ///
    /// A primary falls back to `maximums` when the snapshot carries no baseline
    /// for it, because an actor with nothing written is at its derived maximum
    /// by definition — which is what keeps a snapshot built before item 20.3
    /// answering the same numbers it always did.
    func entry(at index: Int32) -> ActorValueEntry? {
        guard let fallback = ActorValueIdentity.defaultValue(at: index) else { return nil }
        let baseline = if let kind = ActorValueIdentity.kind(at: index) {
            generalBaseline[index] ?? maximums[kind]
        } else {
            generalBaseline[index] ?? fallback
        }
        return general[index] ?? ActorValueEntry(base: baseline)
    }

    /// What `GetActorValuePercent` and `GetActorValuePercentage` report: the
    /// current value over its ceiling, clamped to 0 ... 1.
    ///
    /// A primary divides by its effective maximum, which is what its bar is
    /// drawn against; everything else divides by its base, which is the only
    /// ceiling it has. A zero or negative denominator reads as 0 rather than
    /// dividing.
    func fraction(at index: Int32) -> Float? {
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

    /// The fraction of incoming damage this actor's resistance at `index`
    /// removes, capped — the read-only half of
    /// `ActorValueRuntime.resistanceFraction(at:on:settings:)`, for a caller
    /// that already holds an observation.
    func resistanceFraction(
        at index: Int32,
        settings: ActorResistanceSettings = .documentedDefaults
    ) -> Float? {
        guard ActorResistance.isPercentage(index: index), let points = value(at: index) else {
            return nil
        }
        return ActorResistance.fraction(
            percentagePoints: points,
            at: index,
            isPlayer: isPlayer,
            settings: settings
        )
    }
}
