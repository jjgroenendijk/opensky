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
// The rule, in one sentence: a primary answers from the typed triple, every
// other vanilla index answers from the stored entry when there is one and from
// the record baseline when there is not, and an index outside the table answers
// nil so the caller can count it.
//
// Documented in docs/engine/actor-values.md.

import Foundation

/// An observation of one actor's values that can answer for any actor value.
nonisolated protocol ActorValueReadable {
    /// Current health, magicka and stamina.
    var current: ActorValues { get }
    /// Re-derived maximums for the three primaries.
    var maximums: ActorValues { get }
    /// Non-primary values this actor has moved off its baseline.
    var general: [Int32: ActorValueEntry] { get }
    /// Non-primary base values this actor's records author.
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

    /// What `GetBaseActorValue` reports for `index`: the re-derived maximum for
    /// a primary, and the stored base for everything else — which is the
    /// record-authored base until something writes one.
    func baseValue(at index: Int32) -> Float? {
        if let kind = ActorValueIdentity.kind(at: index) {
            return maximums[kind]
        }
        return entry(at: index)?.base
    }

    /// `index`'s stored entry, or the unmodified entry its records author.
    /// Nil for a primary and for an index outside the table.
    func entry(at index: Int32) -> ActorValueEntry? {
        guard
            ActorValueIdentity.kind(at: index) == nil,
            let fallback = ActorValueIdentity.defaultValue(at: index)
        else { return nil }
        return general[index] ?? ActorValueEntry(base: generalBaseline[index] ?? fallback)
    }

    /// What `GetActorValuePercent` and `GetActorValuePercentage` report: the
    /// current value over the base, clamped to 0 ... 1. A zero or negative base
    /// reads as 0 rather than dividing.
    func fraction(at index: Int32) -> Float? {
        guard let value = value(at: index), let base = baseValue(at: index) else {
            return nil
        }
        guard base.isFinite, base > 0, value.isFinite else { return 0 }
        return min(max(0, value / base), 1)
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
