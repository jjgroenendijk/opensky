// Where a cast is (issue #470, roadmap item 19.7): the per-hand state machine
// the caster runtime advances, and the outcomes it reports.
//
// A pure value type over a clock, in the shape `ArcheryState` and
// `MeleeCombatState` take: no world, no store, no effects. That is what makes
// the cast tests a list of time steps.
//
// One difference from those two is deliberate and is the milestone's known gap.
// Melee and archery read their timing back out of the behavior graph — the
// engine raises `attackStart` and the *graph* decides when the contact frame
// is. No casting graph is driven yet (M25/M26 owns the animation), so the charge
// here is timed against the SPIT charge time instead. When the graph arrives it
// replaces this clock the same way it replaced melee's, and the phases stay.
//
// ## Where the phases come from
//
// UESP's Magic Overview states both shapes in one paragraph: "Some spells will
// trigger immediately upon being cast and can be maintained as long as held.
// Others require holding to charge the spell and releasing to cast it. Casting a
// spell of either form depletes the caster's magicka based on the cost of the
// spell and will continue to do so if the spell is maintained."
// (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>) The first sentence is
// `concentrating`, the second is `charging` then `ready` then the release.
//
// Documented in docs/engine/magic.md.

import Foundation

/// Where one hand's cast is.
nonisolated enum SpellCastPhase: String, Equatable, Sendable, CaseIterable {
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
    var isCasting: Bool {
        self != .idle
    }
}

/// Why a cast did not happen.
nonisolated enum SpellCastFailure: Equatable, Sendable {
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
    /// The spell's delivery is not self. Aimed, target-actor and
    /// target-location delivery are issue 19.8; this counts them rather than
    /// pretending they landed.
    case deliveryUnsupported(MagicEffectDelivery)
    /// An ability is a permanent effect an actor carries, not something a hand
    /// casts.
    case abilityNotCastable
    /// UESP: "Each Greater Power can only be used once per game day."
    /// (<https://en.uesp.net/wiki/Skyrim:Powers>)
    case powerAlreadyUsedToday(day: Int32)

    var describedReason: String {
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
nonisolated enum SpellCastOutcome: Equatable, Sendable {
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

    var isCast: Bool {
        if case .cast = self {
            return true
        }
        return false
    }

    var failure: SpellCastFailure? {
        if case let .failed(reason) = self {
            return reason
        }
        return nil
    }
}

/// One completed application: what was spent and what landed.
nonisolated struct SpellCastResult: Equatable, Sendable {
    let spell: ReferenceKey
    let hand: SpellHand
    /// Magicka actually taken off the caster.
    let magickaSpent: Float
    /// Effect entries handed to the active-effect runtime.
    let entryCount: Int
    /// Timed effects it stored. Zero for a spell whose entries are all instant,
    /// which is what a restore-health cast is.
    let storedCount: Int
}

/// One hand's cast, advanced by time.
///
/// Deliberately not a world-state component: a charge in progress is frame
/// state, and a save that restored one would put the player back mid-cast with
/// magicka already committed. The readied spell persists; the cast does not.
nonisolated struct SpellCastState: Equatable, Sendable {
    private(set) var phase = SpellCastPhase.idle
    /// The spell this cast is of, nil while idle.
    private(set) var spell: ReferenceKey?
    /// Seconds spent charging so far.
    private(set) var charged: Float = 0
    /// Seconds the concentration has been maintained.
    private(set) var held: Float = 0
    /// Whole seconds of concentration whose effect application already
    /// happened. Counted rather than derived from `held`, for the reason
    /// `ActiveEffect.paidSeconds` is: repeated small steps must not round into
    /// an extra application.
    private(set) var appliedSeconds: UInt32 = 0
    /// Magicka this cast has taken so far, which for a concentration spell
    /// grows for as long as it runs.
    private(set) var magickaSpent: Float = 0
    /// True once the input was released but the concentration has not yet
    /// reached the SPIT minimum cast duration.
    private(set) var isReleasing = false

    /// Starts a charge.
    mutating func beginCharge(_ spell: ReferenceKey) {
        self = SpellCastState()
        self.spell = spell
        phase = .charging
    }

    /// Moves a fully charged fire-and-forget cast to the release window.
    mutating func makeReady() {
        phase = .ready
    }

    /// Moves a fully charged concentration cast to maintenance.
    mutating func beginConcentration() {
        phase = .concentrating
    }

    mutating func addCharge(_ delta: Float) {
        charged += delta
    }

    mutating func addHeld(_ delta: Float) {
        held += delta
    }

    mutating func noteApplied() {
        appliedSeconds += 1
    }

    mutating func spend(_ magicka: Float) {
        magickaSpent += magicka
    }

    mutating func requestRelease() {
        isReleasing = true
    }

    /// Ends the cast, leaving the hand idle.
    mutating func finish() {
        self = SpellCastState()
    }

    /// How close to a whole second counts as one.
    ///
    /// The same arithmetic detail `ActiveEffectRuntime` documents, and a real
    /// failure the suites caught rather than a theoretical one: the simulation
    /// step is 1/60 s, which has no exact binary representation, so sixty steps
    /// sum to slightly under one second. Without the tolerance a maintained
    /// spell would skip an application every second.
    static let secondTolerance: Float = 0.001

    /// Applications that are due but have not happened yet, capped at the steps
    /// one advance may run so a stalled frame cannot apply a minute of healing
    /// at once.
    ///
    /// One at entry plus one per whole second held, which is why the count is
    /// `elapsed + 1`: a maintained heal starts healing when it starts costing
    /// rather than a second later.
    func pendingApplications(limit: Int) -> Int {
        let elapsed = UInt32(max(0, held + Self.secondTolerance).rounded(.down))
        let due = elapsed &+ 1
        guard due > appliedSeconds else { return 0 }
        return min(Int(due - appliedSeconds), limit)
    }
}
