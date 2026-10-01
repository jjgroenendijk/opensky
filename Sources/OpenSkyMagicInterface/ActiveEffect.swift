// One magic effect acting on an actor. The Recover flag picks the mode
// (<https://ck.uesp.net/wiki/Magic_Effect>): `modifier` holds a temporary slice
// and returns it on expiry; `perSecond` pays out each second and reverses nothing.
// A zero-duration effect applies once and is never stored. Tapering is not
// applied; no vanilla effect used here needs it. See docs/engine/magic.md.

import Foundation
import OpenSkyFormatsESM

/// Which kind of record handed an effect to an actor.
///
/// The raw values are the save encoding and must not be renumbered.
nonisolated public enum ActiveEffectSourceKind: UInt32, CaseIterable, Hashable, Sendable {
    /// An ALCH ingestible — a potion, a poison, food or drink.
    case potion = 0
    /// An INGR ingredient eaten raw.
    case ingredient = 1
    /// A SPEL or SCRL cast at the actor (issues 19.7 and 19.8).
    case spell = 2
    /// An ENCH enchantment that fired.
    case enchantment = 3
    /// A SPEL an owned PERK grants as a constant ability. Not `spell`, because
    /// losing the perk removes it, not a dispel.
    case perk = 4

    public var describedName: String {
        switch self {
        case .potion: "potion"
        case .ingredient: "ingredient"
        case .spell: "spell"
        case .enchantment: "enchantment"
        case .perk: "perk"
        }
    }
}

/// What applied an effect: the kind of record and which record it was.
///
/// The record travels as a `ReferenceKey` rather than a `FormID` for the reason
/// `QuestRuntimeState` keys a QUST that way — the key is already load-order
/// resolved and already has a save encoding, and a base record that belongs to
/// no cell is exactly what it addresses.
nonisolated public struct ActiveEffectSource: Equatable, Hashable, Sendable {
    public let kind: ActiveEffectSourceKind
    /// The ALCH, INGR, SPEL or ENCH record the effect list came from.
    public let record: ReferenceKey

    public init(kind: ActiveEffectSourceKind, record: ReferenceKey) {
        self.kind = kind
        self.record = record
    }
}

/// How a timed effect maintains itself over its duration. See the file header
/// for the cited rule that selects between the first two.
///
/// The raw values are the save encoding and must not be renumbered.
nonisolated public enum ActiveEffectMode: UInt32, CaseIterable, Hashable, Sendable {
    /// Recover set: the magnitude is held in the temporary modifier slot for
    /// the whole duration and handed back on expiry.
    case modifier = 0
    /// Recover clear: the magnitude is paid into the value once per completed
    /// second and never taken back.
    case perSecond = 1
    /// A constant effect: held in the temporary slot like `modifier`, with no timer.
    /// Armor enchantments must be constant (<https://ck.uesp.net/wiki/Enchantment>),
    /// so only taking the item off removes it.
    case constant = 2

    /// Whether this mode owns a slice of its actor values' temporary modifier
    /// slot for as long as the effect exists.
    public var ownsModifierSlot: Bool {
        self != .perSecond
    }
}

/// One actor value an effect acts on.
///
/// A Value Modifier or Peak Value Modifier effect has exactly one of these; a
/// Dual Value Modifier has two, the second already scaled by the MGEF's second
/// actor-value weight.
nonisolated public struct ActiveEffectValue: Equatable, Sendable {
    /// Vanilla actor-value table index, as `ActorValueIdentity` numbers it.
    public let index: Int32
    /// EFIT magnitude for this value, always non-negative. Which direction it
    /// moves the value is the effect's `isDetrimental` flag, not this number's
    /// sign, because that is how the record spells it.
    public let magnitude: Float
    /// How much of `index`'s temporary modifier slot this effect currently
    /// owns, signed. Always zero for a `perSecond` effect, which owns no slot.
    public private(set) var applied: Float

    public init(index: Int32, magnitude: Float, applied: Float = 0) {
        self.index = index
        self.magnitude = magnitude.isFinite ? max(0, magnitude) : 0
        self.applied = applied.isFinite ? applied : 0
    }

    /// This value recorded as owning `amount` of the modifier slot.
    public func owning(_ amount: Float) -> ActiveEffectValue {
        ActiveEffectValue(index: index, magnitude: magnitude, applied: amount)
    }
}

/// One effect currently acting on one actor.
///
/// A value type: the component stores an array of them and every mutation
/// returns a new one, which is what lets the runtime compute a whole tick and
/// write the result once.
nonisolated public struct ActiveEffect: Equatable, Sendable {
    /// Per-actor application number, ascending, from `ActiveEffectState`. Two
    /// doses of one potion are two effects. Per component, so a save needs no allocator.
    public let sequence: UInt64
    public let source: ActiveEffectSource
    /// The MGEF this is an application of.
    public let effect: ReferenceKey
    /// The actor that applied it, where one is known. Nil for a potion the
    /// player drank, which nobody cast.
    public let caster: ReferenceKey?
    public let mode: ActiveEffectMode
    /// MGEF Detrimental: the magnitude is taken off the actor value rather than
    /// added to it.
    public let isDetrimental: Bool
    /// EFIT duration in seconds. Always above zero for a timed effect — a
    /// zero-duration one applies once and is never stored — and normally zero
    /// for a `constant` effect, which no duration bounds.
    public let duration: Float
    /// Seconds since application, capped at `duration`.
    public private(set) var elapsed: Float
    /// Whole seconds a `perSecond` effect has already paid out, so a tick that
    /// crosses two second boundaries pays twice and one that crosses none pays
    /// nothing.
    public private(set) var paidSeconds: UInt32
    /// The actor values this effect acts on, in the order the MGEF names them.
    public private(set) var values: [ActiveEffectValue]
    /// Peak Value Modifier's second associated item: the keyword two effects
    /// must share before the weaker of them is dispelled.
    public let stackKeyword: ReferenceKey?

    public init(
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

    /// Whether nothing but an explicit removal ends this effect.
    public var isConstant: Bool {
        mode == .constant
    }

    /// Seconds left before the effect expires. Zero for a constant effect,
    /// which has no remaining duration to report; ask `isConstant` first.
    public var remaining: Float {
        max(0, duration - elapsed)
    }

    public var isExpired: Bool {
        !isConstant && elapsed >= duration
    }

    /// The largest magnitude the effect carries, which is what the Peak Value
    /// Modifier stacking rule compares.
    public var peakMagnitude: Float {
        values.map(\.magnitude).max() ?? 0
    }

    /// Tolerance for counting a whole second. Sixty 1/60 s steps sum to just under
    /// one second, which made effects expire a step late and skip their last payout.
    /// A millisecond is far above the error and far below what a player sees.
    public static let secondTolerance: Float = 1e-3

    /// This effect advanced by `seconds`, clamped at its duration.
    ///
    /// An effect with less than half a step left is snapped to its duration
    /// rather than left a microsecond short: it cannot survive another step
    /// either way, and the snap is what makes expiry land on the step the
    /// duration names instead of the one after it.
    public func advanced(by seconds: Float) -> ActiveEffect {
        guard !isConstant, seconds.isFinite, seconds > 0 else { return self }
        var copy = self
        let next = elapsed + seconds
        copy.elapsed = duration - next < seconds / 2 ? duration : min(duration, next)
        return copy
    }

    /// Whole seconds a `perSecond` effect owes but has not paid. A ten-second
    /// effect pays ten times, the first after one second. The payout count is
    /// stored, so small ticks cannot round into an extra payment.
    public var unpaidSeconds: UInt32 {
        guard mode == .perSecond else { return 0 }
        let whole = UInt32(clamping: Int((elapsed + Self.secondTolerance).rounded(.down)))
        return whole > paidSeconds ? whole - paidSeconds : 0
    }

    /// This effect with `count` more whole seconds recorded as paid.
    public func paying(_ count: UInt32) -> ActiveEffect {
        var copy = self
        copy.paidSeconds = paidSeconds &+ count
        return copy
    }

    /// This effect recording that it now owns `amounts[index]` of each named
    /// value's temporary modifier slot.
    public func owningModifiers(_ amounts: [Int32: Float]) -> ActiveEffect {
        var copy = self
        copy.values = values.map { value in
            guard let amount = amounts[value.index] else { return value }
            return value.owning(amount)
        }
        return copy
    }

    /// The signed change one application of `value` makes to an actor value.
    public func delta(of value: ActiveEffectValue) -> Float {
        isDetrimental ? -value.magnitude : value.magnitude
    }
}
