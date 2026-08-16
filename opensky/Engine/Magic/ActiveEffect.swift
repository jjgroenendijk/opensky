// One magic effect currently acting on an actor (issue #469, roadmap item
// 19.6): what was applied, by what, to which actor values, and how much of the
// duration is left.
//
// ## The two ways a timed effect works
//
// The Creation Kit wiki's Magic Effect page states the rule the Recover flag
// selects, and it is the whole reason this type carries a mode:
//
//   "Recover: When this Effect expires, the attribute returns to its previous
//   state. If checked, Value Modifier and Peak Value Modifier archetypes will
//   modify their actor value once at the start, then modify it back once the
//   Effect expires; if unchecked, the actor value will get modified every
//   second and will not be reset at the end."
//   (<https://ck.uesp.net/wiki/Magic_Effect>, read through the Wayback Machine
//   because the live host refuses automated requests.)
//
// So a `modifier` effect owns a slice of its actor values' temporary modifier
// slot for the whole duration and hands it back on expiry, and a `perSecond`
// effect pays its magnitude out once per completed second and reverses nothing.
// A zero-duration effect is neither: it applies once and is never stored, which
// is why `ActiveEffectMode` has no `instant` case.
//
// ## What is deliberately not modelled
//
// Tapering (the MGEF taper weight, curve and duration) is not applied. The same
// page documents the formula, but no vanilla potion or ingredient effect this
// item consumes uses it, so implementing it here would be untested ground; it
// is named in docs/engine/magic.md as a known gap rather than silently ignored.
//
// Documented in docs/engine/magic.md.

import Foundation

/// Which kind of record handed an effect to an actor.
///
/// The raw values are the save encoding and must not be renumbered.
nonisolated enum ActiveEffectSourceKind: UInt32, CaseIterable, Hashable, Sendable {
    /// An ALCH ingestible — a potion, a poison, food or drink.
    case potion = 0
    /// An INGR ingredient eaten raw.
    case ingredient = 1
    /// A SPEL or SCRL cast at the actor (issues 19.7 and 19.8).
    case spell = 2
    /// An ENCH enchantment that fired (issue 19.9).
    case enchantment = 3

    var describedName: String {
        switch self {
        case .potion: "potion"
        case .ingredient: "ingredient"
        case .spell: "spell"
        case .enchantment: "enchantment"
        }
    }
}

/// What applied an effect: the kind of record and which record it was.
///
/// The record travels as a `ReferenceKey` rather than a `FormID` for the reason
/// `QuestRuntimeState` keys a QUST that way — the key is already load-order
/// resolved and already has a save encoding, and a base record that belongs to
/// no cell is exactly what it addresses.
nonisolated struct ActiveEffectSource: Equatable, Hashable, Sendable {
    let kind: ActiveEffectSourceKind
    /// The ALCH, INGR, SPEL or ENCH record the effect list came from.
    let record: ReferenceKey
}

/// How a timed effect maintains itself over its duration. See the file header
/// for the cited rule that selects between the two.
///
/// The raw values are the save encoding and must not be renumbered.
nonisolated enum ActiveEffectMode: UInt32, CaseIterable, Hashable, Sendable {
    /// Recover set: the magnitude is held in the temporary modifier slot for
    /// the whole duration and handed back on expiry.
    case modifier = 0
    /// Recover clear: the magnitude is paid into the value once per completed
    /// second and never taken back.
    case perSecond = 1
}

/// One actor value an effect acts on.
///
/// A Value Modifier or Peak Value Modifier effect has exactly one of these; a
/// Dual Value Modifier has two, the second already scaled by the MGEF's second
/// actor-value weight.
nonisolated struct ActiveEffectValue: Equatable, Sendable {
    /// Vanilla actor-value table index, as `ActorValueIdentity` numbers it.
    let index: Int32
    /// EFIT magnitude for this value, always non-negative. Which direction it
    /// moves the value is the effect's `isDetrimental` flag, not this number's
    /// sign, because that is how the record spells it.
    let magnitude: Float
    /// How much of `index`'s temporary modifier slot this effect currently
    /// owns, signed. Always zero for a `perSecond` effect, which owns no slot.
    private(set) var applied: Float

    init(index: Int32, magnitude: Float, applied: Float = 0) {
        self.index = index
        self.magnitude = magnitude.isFinite ? max(0, magnitude) : 0
        self.applied = applied.isFinite ? applied : 0
    }

    /// This value recorded as owning `amount` of the modifier slot.
    func owning(_ amount: Float) -> ActiveEffectValue {
        ActiveEffectValue(index: index, magnitude: magnitude, applied: amount)
    }
}

/// One effect currently acting on one actor.
///
/// A value type: the component stores an array of them and every mutation
/// returns a new one, which is what lets the runtime compute a whole tick and
/// write the result once.
nonisolated struct ActiveEffect: Equatable, Sendable {
    /// Per-actor application number, assigned by `ActiveEffectState` in
    /// ascending order.
    ///
    /// Two applications of the same effect from the same potion are genuinely
    /// two effects, so they need something to tell them apart that is neither
    /// the MGEF nor the source record. Assigned by the component rather than by
    /// a global allocator so it survives a save round trip without the save
    /// having to carry an allocator of its own.
    let sequence: UInt64
    let source: ActiveEffectSource
    /// The MGEF this is an application of.
    let effect: ReferenceKey
    /// The actor that applied it, where one is known. Nil for a potion the
    /// player drank, which nobody cast.
    let caster: ReferenceKey?
    let mode: ActiveEffectMode
    /// MGEF Detrimental: the magnitude is taken off the actor value rather than
    /// added to it.
    let isDetrimental: Bool
    /// EFIT duration in seconds. Always above zero — a zero-duration effect
    /// applies once and is never stored.
    let duration: Float
    /// Seconds since application, capped at `duration`.
    private(set) var elapsed: Float
    /// Whole seconds a `perSecond` effect has already paid out, so a tick that
    /// crosses two second boundaries pays twice and one that crosses none pays
    /// nothing.
    private(set) var paidSeconds: UInt32
    /// The actor values this effect acts on, in the order the MGEF names them.
    private(set) var values: [ActiveEffectValue]
    /// Peak Value Modifier's second associated item: the keyword two effects
    /// must share before the weaker of them is dispelled.
    let stackKeyword: ReferenceKey?

    init(
        sequence: UInt64,
        source: ActiveEffectSource,
        effect: ReferenceKey,
        caster: ReferenceKey? = nil,
        mode: ActiveEffectMode,
        isDetrimental: Bool,
        duration: Float,
        elapsed: Float = 0,
        paidSeconds: UInt32 = 0,
        values: [ActiveEffectValue],
        stackKeyword: ReferenceKey? = nil
    ) {
        self.sequence = sequence
        self.source = source
        self.effect = effect
        self.caster = caster
        self.mode = mode
        self.isDetrimental = isDetrimental
        self.duration = duration.isFinite ? max(0, duration) : 0
        self.elapsed = elapsed.isFinite ? min(max(0, elapsed), self.duration) : 0
        self.paidSeconds = paidSeconds
        self.values = values
        self.stackKeyword = stackKeyword
    }

    /// Seconds left before the effect expires.
    var remaining: Float {
        max(0, duration - elapsed)
    }

    var isExpired: Bool {
        elapsed >= duration
    }

    /// The largest magnitude the effect carries, which is what the Peak Value
    /// Modifier stacking rule compares.
    var peakMagnitude: Float {
        values.map(\.magnitude).max() ?? 0
    }

    /// Tolerance a whole second is counted within.
    ///
    /// The simulation step is 1/60 s, which has no exact binary representation,
    /// so sixty of them sum to slightly under one second and a hundred and
    /// twenty to slightly under two. Without a tolerance an effect would take
    /// one extra step to expire and a per-second effect would skip its last
    /// pay-out — a real failure the suites caught, not a theoretical one. A
    /// millisecond is far below anything a player can observe and far above the
    /// accumulated error, which is on the order of a microsecond per second.
    static let secondTolerance: Float = 1e-3

    /// This effect advanced by `seconds`, clamped at its duration.
    ///
    /// An effect with less than half a step left is snapped to its duration
    /// rather than left a microsecond short: it cannot survive another step
    /// either way, and the snap is what makes expiry land on the step the
    /// duration names instead of the one after it.
    func advanced(by seconds: Float) -> ActiveEffect {
        guard seconds.isFinite, seconds > 0 else { return self }
        var copy = self
        let next = elapsed + seconds
        copy.elapsed = duration - next < seconds / 2 ? duration : min(duration, next)
        return copy
    }

    /// How many whole seconds a `perSecond` effect owes but has not paid.
    ///
    /// A second is owed once it has fully elapsed, so an effect with a duration
    /// of ten seconds pays ten times, the first payment landing one second after
    /// it was applied. The pay-out count is stored rather than derived from
    /// `elapsed` alone so that repeated small ticks cannot round into an extra
    /// payment.
    var unpaidSeconds: UInt32 {
        guard mode == .perSecond else { return 0 }
        let whole = UInt32(clamping: Int((elapsed + Self.secondTolerance).rounded(.down)))
        return whole > paidSeconds ? whole - paidSeconds : 0
    }

    /// This effect with `count` more whole seconds recorded as paid.
    func paying(_ count: UInt32) -> ActiveEffect {
        var copy = self
        copy.paidSeconds = paidSeconds &+ count
        return copy
    }

    /// This effect recording that it now owns `amounts[index]` of each named
    /// value's temporary modifier slot.
    func owningModifiers(_ amounts: [Int32: Float]) -> ActiveEffect {
        var copy = self
        copy.values = values.map { value in
            guard let amount = amounts[value.index] else { return value }
            return value.owning(amount)
        }
        return copy
    }

    /// The signed change one application of `value` makes to an actor value.
    func delta(of value: ActiveEffectValue) -> Float {
        isDetrimental ? -value.magnitude : value.magnitude
    }
}
