// Where a cast is: the per-hand state machine and its outcomes. A pure value
// type over a clock. No casting graph is driven yet, so the charge is timed by
// SPIT. UESP's Magic Overview gives the two shapes: concentration, and charge
// then release (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>).
// See docs/engine/spellcasting.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyMagicInterface

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
    /// The spell's delivery is not self. This hand path counts
    /// other deliveries rather than pretending they landed.
    case deliveryUnsupported(MagicEffectDelivery)
    /// An ability is a permanent effect an actor carries, not something a hand
    /// casts.
    case abilityNotCastable
    /// UESP: "Each Greater Power can only be used once per game day."
    /// (<https://en.uesp.net/wiki/Skyrim:Powers>)
    case powerAlreadyUsedToday(day: Int32)

    public var describedReason: String {
        switch self {
        case let .noSpellReadied(hand): "no spell readied in the \(hand.describedName)"
        case let .unknownSpell(spell): "no loaded plugin carries \(spell)"
        case let .notCharged(remaining):
            String(format: "released %.2fs before the charge finished", remaining)
        case let .insufficientMagicka(cost, available):
            String(format: "not enough magicka: %.0f needed, %.0f available", cost, available)
        case let .deliveryUnsupported(delivery):
            "\(delivery) delivery is not implemented yet"
        case .abilityNotCastable: "an ability is carried, not cast"
        case let .powerAlreadyUsedToday(day): "this power was already used on day \(day)"
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
}

/// One hand's cast, advanced by time.
///
/// Deliberately not a world-state component: a charge in progress is frame
/// state, and a save that restored one would put the player back mid-cast with
/// magicka already committed. The readied spell persists; the cast does not.
nonisolated public struct SpellCastState: Equatable, Sendable {
    public private(set) var phase = SpellCastPhase.idle
    /// The spell this cast is of, nil while idle.
    public private(set) var spell: ReferenceKey?
    /// Seconds spent charging so far.
    public private(set) var charged: Float = 0
    /// Seconds the concentration has been maintained.
    public private(set) var held: Float = 0
    /// Whole seconds of concentration whose effect application already
    /// happened. Counted rather than derived from `held`, for the reason
    /// `ActiveEffect.paidSeconds` is: repeated small steps must not round into
    /// an extra application.
    public private(set) var appliedSeconds: UInt32 = 0
    /// Magicka this cast has taken so far, which for a concentration spell
    /// grows for as long as it runs.
    public private(set) var magickaSpent: Float = 0
    /// True once the input was released but the concentration has not yet
    /// reached the SPIT minimum cast duration.
    public private(set) var isReleasing = false

    /// Starts a charge.
    public mutating func beginCharge(_ spell: ReferenceKey) {
        self = SpellCastState()
        phase = .charging
        self.spell = spell
    }

    /// Moves a fully charged fire-and-forget cast to the release window.
    public mutating func makeReady() {
        phase = .ready
    }

    /// Moves a fully charged concentration cast to maintenance.
    public mutating func beginConcentration() {
        phase = .concentrating
    }

    public mutating func addCharge(_ delta: Float) {
        charged += delta
    }

    public mutating func addHeld(_ delta: Float) {
        held += delta
    }

    public mutating func noteApplied() {
        appliedSeconds += 1
    }

    public mutating func spend(_ magicka: Float) {
        magickaSpent += magicka
    }

    public mutating func requestRelease() {
        isReleasing = true
    }

    /// How close to a whole second counts as one. Sixty 1/60 s steps sum to just
    /// under one second in binary floating point; without this tolerance a
    /// maintained spell would skip an application.
    public static let secondTolerance: Float = 0.001

    /// Applications that are due, capped at the steps one advance may run. One at
    /// entry plus one per whole second held, hence `elapsed + 1`.
    public func pendingApplications(limit: Int) -> Int {
        let elapsed = UInt32(max(0, held + Self.secondTolerance).rounded(.down))
        let due = elapsed &+ 1
        guard due > appliedSeconds else { return 0 }
        return min(Int(due - appliedSeconds), limit)
    }
}
