import Foundation
public import OpenSkyFormatsESM

/// Why a cast did not happen.
nonisolated public enum SpellCastFailure: Equatable, Sendable {
    /// No spell is readied in the hand that was asked to cast.
    case noSpellReadied(SpellHand)
    /// A spell is readied but this load order no longer carries the record.
    case unknownSpell(ReferenceKey)
    /// The cast input was released before the charge time elapsed.
    case notCharged(remaining: Float)
    /// UESP: "Attempting to cast a spell with a cost higher than your available
    /// magicka will result in the failure of the attempted casting."
    /// (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>) For a concentration
    /// spell the same rule ends a cast already running, because the cost keeps
    /// being charged for as long as it is maintained.
    case insufficientMagicka(cost: Float, available: Float)
    /// A staff's charge is below one use. UESP "Skyrim:Staves": a staff "depletes the
    /// staff's charge" and an empty one is "unusable".
    case staffOutOfCharge(cost: Float, available: Float)
    /// The spell's delivery is not self. This hand path counts
    /// other deliveries rather than pretending they landed.
    case deliveryUnsupported(MagicEffectDelivery)
    /// An ability is a permanent effect an actor carries, not something a hand
    /// casts.
    case abilityNotCastable
    /// UESP: "Each Greater Power can only be used once per game day."
    /// (<https://en.uesp.net/wiki/Skyrim:Powers>)
    case powerAlreadyUsedToday(day: Int32)
    /// Both hands began the spell, but no perk lets this caster dual cast it.
    case notDualCastable
    /// The caster rides a flying dragon, and this kind of spell cannot be cast from it.
    case notFromFlyingMount

    public var describedReason: String {
        switch self {
        case let .noSpellReadied(hand): "no spell readied in the \(hand.describedName)"
        case let .unknownSpell(spell): "no loaded plugin carries \(spell)"
        case let .notCharged(remaining):
            unsafe String(format: "released %.2fs before the charge finished", remaining)
        case let .insufficientMagicka(cost, available):
            unsafe String(
                format: "not enough magicka: %.0f needed, %.0f available",
                cost,
                available
            )
        case let .staffOutOfCharge(cost, available):
            unsafe String(
                format: "not enough staff charge: %.0f needed, %.0f left",
                cost,
                available
            )
        case let .deliveryUnsupported(delivery):
            "\(delivery) delivery is not implemented yet"
        case .abilityNotCastable: "an ability is carried, not cast"
        case let .powerAlreadyUsedToday(day): "this power was already used on day \(day)"
        case .notDualCastable: "no dual casting perk covers this spell"
        case .notFromFlyingMount: "this kind of spell cannot be cast from a flying dragon"
        }
    }
}

/// What one cast action did.
nonisolated public enum SpellCastOutcome: Equatable, Sendable {
    /// The charge started. Carries the seconds until the spell is castable, so
    /// a caller can tell an instant-charge spell from one that has to be held.
    case charging(spell: ReferenceKey, chargeTime: Float)
    /// A fire-and-forget spell finished charging and is waiting for the
    /// release that spends it.
    case ready(hand: SpellHand, spell: ReferenceKey)
    /// A concentration cast began and is now draining.
    case concentrating(spell: ReferenceKey, costPerSecond: Float)
    /// The spell was cast: the magicka was spent and the effect list applied.
    case cast(SpellCastResult)
    /// A maintained cast ended because the input was released or its minimum
    /// duration ran out.
    case released(spell: ReferenceKey, heldSeconds: Float, magickaSpent: Float)
    /// Nothing happened and this is why.
    case failed(SpellCastFailure)
    /// The hand was idle and the action asked nothing of it.
    case ignored

    public var isCast: Bool {
        if case .cast = self {
            return true
        }
        return false
    }

    /// Whether a spell left the hand: a fire-and-forget one landed, or a maintained
    /// one ran and was let go. The combat loop counts this as a cast.
    public var isFinished: Bool {
        switch self {
        case .cast, .released: true
        default: false
        }
    }

    public var failure: SpellCastFailure? {
        if case let .failed(reason) = self {
            return reason
        }
        return nil
    }
}

/// One completed application: what was spent and what landed.
nonisolated public struct SpellCastResult: Equatable, Sendable {
    /// Magicka actually taken off the caster.
    public let magickaSpent: Float
    /// Effect entries handed to the active-effect runtime.
    public let entryCount: Int
    /// Timed effects it stored. Zero for a spell whose entries are all instant,
    /// which is what a restore-health cast is.
    public let storedCount: Int
    /// Both hands cast it together.
    public var isDualCast = false

    public init(
        magickaSpent: Float,
        entryCount: Int,
        storedCount: Int,
        isDualCast: Bool = false
    ) {
        self.magickaSpent = magickaSpent
        self.entryCount = entryCount
        self.storedCount = storedCount
        self.isDualCast = isDualCast
    }
}

/// Where one hand's cast is.
nonisolated public enum SpellCastPhase: String, Equatable, Sendable, CaseIterable {
    /// Nothing is being cast in this hand.
    case idle
    /// The cast input is held and the SPIT charge time has not elapsed.
    /// Releasing here casts nothing.
    case charging
    /// A fire-and-forget spell is fully charged and waiting for the release
    /// that spends the magicka and applies the effects.
    case ready
    /// A concentration spell is being maintained: magicka drains and the effect
    /// list lands once per whole second held.
    case concentrating

    /// Whether the hand is doing anything at all, which is what a readout means
    /// by "casting" and what magicka regeneration has to stand down for. UESP:
    /// "Magicka will not regenerate while you are casting a spell."
    /// (<https://en.uesp.net/wiki/Skyrim:Magicka>)
    public var isCasting: Bool {
        self != .idle
    }
}
