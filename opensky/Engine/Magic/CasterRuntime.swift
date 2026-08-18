// The cast loop (issue #470, roadmap item 19.7): turning "cast with this hand"
// into spent magicka and an applied effect list, for the self-delivery half of
// casting. Aimed delivery and projectiles are issue 19.8.
//
// Main-actor and driven from the frame the renderer already runs there, like
// the other directors. Everything it touches the world with goes through
// `CasterWorld`, so the whole runtime is testable against a fake with no store,
// no records and no window — the same seam `MeleeCombatWorld` is.
//
// ## The order a fire-and-forget cast runs in
//
//   1. `begin(_:on:)` — the readied spell is resolved, the refusals are checked,
//      and the hand enters `charging`. A spell with no charge time reaches
//      `ready` on the same call.
//   2. `advance(delta:on:)` — the charge accumulates and the hand reaches
//      `ready`.
//   3. `release(_:on:)` — the cost is checked against magicka, taken off, and
//      the effect list is handed to the active-effect runtime.
//
// Magicka is checked twice, at step 1 and again at step 3, because it can fall
// between them: a charge takes half a second and something can hit the caster
// inside it. UESP states the rule once — "Attempting to cast a spell with a cost
// higher than your available magicka will result in the failure of the attempted
// casting" (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>) — and checking it
// at both ends is the reading that never lets a cast land unpaid.
//
// ## And a concentration cast
//
// `begin` reaches `concentrating` and stays there. Cost is charged
// continuously, so the magicka bar moves smoothly rather than in one-second
// steps, and the effect list is applied once on entry and once per whole second
// after that. UESP: "Concentration spells do not have a set duration. Rather,
// the duration is determined by how long you hold the casting trigger."
// (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>) The SPIT cast duration is
// the floor under that: a release inside it keeps the cast running until it
// elapses.
//
// Documented in docs/engine/magic.md.

import Foundation
import simd

/// What a cast needs from the world it happens in.
///
/// A protocol rather than the concrete runtimes for the reason
/// `MeleeCombatWorld` is one: the active-effect runtime is a mutating value over
/// a shared store, and a copy held here would grow a tally the panel never sees.
///
/// It refines `SpellHitApplying` (issue #471) so a spell that leaves the caster
/// lands through the same one implementation a projectile's does.
@MainActor
protocol CasterWorld: SpellHitApplying {
    /// Whole game days elapsed, which is what the once-per-day power rule
    /// compares.
    var castingGameDay: Int32 { get }

    /// Applies one spell's effect list to `target`.
    ///
    /// - Returns: how many timed effects were stored.
    func applyCastEffects(
        _ entries: [MagicItemEffect],
        fromPlugin pluginName: String,
        source: ActiveEffectSource,
        caster: ReferenceKey,
        on target: ActorValueHolder
    ) -> Int

    /// Launches `payload`'s projectile from the caster along the aim ray
    /// (issue #471).
    ///
    /// - Returns: false when nothing left the caster — the MGEF names no PROJ,
    ///   this load order does not carry it, or the record is not one the flight
    ///   model can integrate. Counted rather than silent.
    @discardableResult
    func fireSpellProjectile(_ payload: SpellPayload) -> Bool

    /// What `caster`'s aim ray reaches, for the deliveries that need a target
    /// rather than a projectile.
    ///
    /// The caster is a parameter rather than an implied player because item
    /// 19.10 casts an NPC's spells through this same runtime: the player aims
    /// down the camera ray and an NPC aims from its own eye at whatever it is
    /// fighting, and only the session knows either.
    ///
    /// - Parameter range: SPIT's range in world units. Zero means the record
    ///   bounds nothing and the session's own maximum applies, which is the
    ///   same rule a PROJ with no range flies under.
    func aimedSpellTarget(within range: Float, for caster: ReferenceKey) -> SpellAim
}

/// One cast in flight, identified by who is casting and in which hand.
///
/// A key rather than a nested dictionary because every lookup needs both
/// halves and neither is meaningful alone: "the right hand" is not a cast until
/// somebody is doing it (issue #473).
nonisolated struct CastSlot: Hashable, Sendable {
    let caster: ReferenceKey
    let hand: SpellHand
}

/// Where a caster is aiming, and what is standing there.
nonisolated struct SpellAim: Equatable, Sendable {
    /// The actor the aim ray reached, or nil when it reached nobody.
    let target: ReferenceKey?
    /// Where the ray ended, world space — the actor it found, or the far end of
    /// the range. What an area application measures its radius from.
    let position: SIMD3<Float>
    /// Every actor a landed spell could catch, for the area rule.
    let candidates: [MeleeTarget]

    init(
        target: ReferenceKey? = nil,
        position: SIMD3<Float> = SIMD3<Float>(),
        candidates: [MeleeTarget] = []
    ) {
        self.target = target
        self.position = position
        self.candidates = candidates
    }

    /// The reading a session with no world can give.
    static let none = SpellAim()
}

@MainActor
final class CasterRuntime {
    /// Most whole applications one `advance` may run for a maintained cast, so
    /// a multi-second stall cannot land a minute of healing in one frame. The
    /// same cap `ActiveEffectRuntime` puts on its steps.
    static let maximumApplicationsPerAdvance = ActiveEffectRuntime.maximumStepsPerAdvance

    let spellbook: SpellbookRuntime
    let values: ActorValueRuntime
    /// What the loop did and declined to do. Not `private(set)`: the ability
    /// half lives in `CasterRuntimeAbilities.swift` and a file-private setter
    /// would put it out of reach there, the same reason
    /// `ActiveEffectRuntime.tally` is internal.
    var tally = CastingTally()
    /// The most recent outcome per hand, for a readout. The player's hands
    /// alone: an NPC's casts are reported through the combat loop's own
    /// readout, and letting every actor in a fight overwrite this would make
    /// the panel line say whatever the last skeever did.
    private(set) var lastOutcome: [SpellHand: SpellCastOutcome] = [:]

    /// The world a cast happens in. Readable across the satellites for the
    /// reason `tally` is settable across them.
    private(set) weak var world: (any CasterWorld)?
    /// Every cast in flight, keyed by the actor casting and the hand it is in.
    ///
    /// Not `private`: the concentration half lives in
    /// `CasterRuntimeConcentration.swift`, the same reason `tally` is internal.
    ///
    /// Keyed by actor rather than by hand alone because item 19.10 casts an
    /// NPC's spells through this same runtime: two actors charging at once are
    /// two casts, and a hand-keyed dictionary would have the second one
    /// overwrite the first's charge.
    var casts: [CastSlot: SpellCastState] = [:]
    /// Whether each actor's hand button was down on the previous frame, so
    /// `acceptFrame` acts on edges rather than levels. Owned here rather than in
    /// the input satellite because an extension cannot add stored properties.
    private var heldButtons: [CastSlot: Bool] = [:]

    init(
        spellbook: SpellbookRuntime,
        values: ActorValueRuntime,
        world: (any CasterWorld)? = nil
    ) {
        self.spellbook = spellbook
        self.values = values
        self.world = world
    }

    func attach(world: (any CasterWorld)?) {
        self.world = world
        casts = [:]
        heldButtons = [:]
    }

    /// Whether `caster`'s `hand` button was down on the previous frame.
    /// Internal so the input satellite can read it.
    func wasHeld(_ hand: SpellHand, on caster: ReferenceKey = .player) -> Bool {
        heldButtons[CastSlot(caster: caster, hand: hand)] ?? false
    }

    func setHeld(_ hand: SpellHand, _ held: Bool, on caster: ReferenceKey = .player) {
        heldButtons[CastSlot(caster: caster, hand: hand)] = held
    }

    // MARK: - Reading

    func state(of hand: SpellHand, on caster: ReferenceKey = .player) -> SpellCastState {
        casts[CastSlot(caster: caster, hand: hand)] ?? SpellCastState()
    }

    func phase(of hand: SpellHand, on caster: ReferenceKey = .player) -> SpellCastPhase {
        state(of: hand, on: caster).phase
    }

    /// Whether either of `caster`'s hands is mid-cast, which is what magicka
    /// regeneration stands down for.
    func isCasting(_ caster: ReferenceKey = .player) -> Bool {
        SpellHand.allCases.contains { phase(of: $0, on: caster).isCasting }
    }

    /// Every actor with a cast in flight, in key order. What the combat panel
    /// counts so an NPC mid-charge is visible rather than assumed.
    var castingActors: [ReferenceKey] {
        Set(casts.filter(\.value.phase.isCasting).keys.map(\.caster)).sorted()
    }

    // MARK: - Casting

    /// Starts a cast in `hand`.
    @discardableResult
    func begin(_ hand: SpellHand, on caster: ActorValueHolder) -> SpellCastOutcome {
        guard let key = spellbook.state(of: caster).spell(in: hand) else {
            return record(hand, on: caster, .failed(.noSpellReadied(hand)))
        }
        guard let spell = spellbook.record(key) else {
            return record(hand, on: caster, .failed(.unknownSpell(key)))
        }
        if let refusal = refusal(for: spell, key: key, caster: caster) {
            return record(hand, on: caster, .failed(refusal))
        }
        var state = SpellCastState()
        state.beginCharge(key)
        casts[slot(hand, caster)] = state
        let chargeTime = max(0, spell.data?.chargeTime ?? 0)
        guard chargeTime <= 0 else {
            return record(hand, on: caster, .charging(spell: key, chargeTime: chargeTime))
        }
        return record(hand, on: caster, finishCharge(hand, spell: spell, caster: caster))
    }

    /// Releases the cast input in `hand`.
    @discardableResult
    func release(_ hand: SpellHand, on caster: ActorValueHolder) -> SpellCastOutcome {
        var state = state(of: hand, on: caster.key)
        guard let key = state.spell, let spell = spellbook.record(key) else {
            casts[slot(hand, caster)] = SpellCastState()
            return record(hand, on: caster, .ignored)
        }
        switch state.phase {
        case .idle:
            return .ignored
        case .charging:
            let remaining = max(0, (spell.data?.chargeTime ?? 0) - state.charged)
            casts[slot(hand, caster)] = SpellCastState()
            return record(hand, on: caster, .failed(.notCharged(remaining: remaining)))
        case .ready:
            return record(hand, on: caster, cast(hand, spell: spell, caster: caster))
        case .concentrating:
            state.requestRelease()
            casts[slot(hand, caster)] = state
            guard state.held >= max(0, spell.data?.castDuration ?? 0) else {
                return .ignored
            }
            return record(hand, on: caster, stopConcentration(hand, spell: key, caster: caster))
        }
    }

    /// Ends whatever `hand` is doing without casting it.
    func cancel(_ hand: SpellHand, on caster: ActorValueHolder) {
        casts[slot(hand, caster)] = SpellCastState()
    }

    // MARK: - Advancing

    /// Runs one simulated frame of both hands.
    ///
    /// Delta 0 advances nothing, which is what a menu-paused frame delivers —
    /// the same rule regeneration and the effect tick follow.
    func advance(delta: Float, on caster: ActorValueHolder) {
        guard delta > 0 else { return }
        for hand in SpellHand.allCases {
            advance(hand, delta: delta, on: caster)
        }
    }

    // MARK: - Private

    /// Everything that refuses a cast before it starts.
    private func refusal(
        for spell: ResolvedSpell,
        key: ReferenceKey,
        caster: ActorValueHolder
    ) -> SpellCastFailure? {
        guard spell.spellType != .ability else { return .abilityNotCastable }
        let delivery = spell.data?.delivery ?? .selfTarget
        guard SpellDelivery.isImplemented(delivery, castingType: spell.data?.castingType) else {
            return .deliveryUnsupported(delivery)
        }
        if spell.spellType == .power, let world {
            let day = world.castingGameDay
            if spellbook.state(of: caster).hasSpentPower(key, onDay: day) {
                return .powerAlreadyUsedToday(day: day)
            }
        }
        let cost = Float(spell.cost.cost)
        let available = values.current(of: caster).magicka
        guard cost <= available else {
            return .insufficientMagicka(cost: cost, available: available)
        }
        return nil
    }

    private func advance(_ hand: SpellHand, delta: Float, on caster: ActorValueHolder) {
        var state = state(of: hand, on: caster.key)
        guard let key = state.spell, let spell = spellbook.record(key) else { return }
        switch state.phase {
        case .idle, .ready:
            return
        case .charging:
            state.addCharge(delta)
            casts[slot(hand, caster)] = state
            guard state.charged >= max(0, spell.data?.chargeTime ?? 0) else { return }
            record(hand, on: caster, finishCharge(hand, spell: spell, caster: caster))
        case .concentrating:
            record(hand, on: caster, maintain(hand, spell: spell, delta: delta, caster: caster))
        }
    }

    /// The charge finished: a fire-and-forget spell waits for the release, a
    /// concentration spell starts draining immediately.
    private func finishCharge(
        _ hand: SpellHand,
        spell: ResolvedSpell,
        caster: ActorValueHolder
    ) -> SpellCastOutcome {
        var state = state(of: hand, on: caster.key)
        guard spell.data?.castingType == .concentration else {
            state.makeReady()
            casts[slot(hand, caster)] = state
            return .ready(hand: hand, spell: state.spell ?? spell.key)
        }
        state.beginConcentration()
        casts[slot(hand, caster)] = state
        // The first application lands on entry rather than a second later, so a
        // maintained heal starts healing when it starts costing.
        applyOnce(hand, spell: spell, caster: caster)
        return .concentrating(spell: spell.key, costPerSecond: Float(spell.cost.cost))
    }

    /// One fire-and-forget cast: check the cost again, take it, apply the list.
    private func cast(
        _ hand: SpellHand,
        spell: ResolvedSpell,
        caster: ActorValueHolder
    ) -> SpellCastOutcome {
        let cost = Float(spell.cost.cost)
        let available = values.current(of: caster).magicka
        guard cost <= available else {
            casts[slot(hand, caster)] = SpellCastState()
            return .failed(.insufficientMagicka(cost: cost, available: available))
        }
        values.damage(.magicka, by: cost, on: caster)
        let stored = apply(spell, caster: caster)
        casts[slot(hand, caster)] = SpellCastState()
        notePowerSpent(spell, caster: caster)
        tally.noteCast()
        return .cast(SpellCastResult(
            spell: spell.key,
            hand: hand,
            magickaSpent: cost,
            entryCount: spell.record.effects.count,
            storedCount: stored
        ))
    }

    /// Delivers one application of `spell`.
    ///
    /// Self delivery hands the effect list straight to the active-effect
    /// runtime with the caster as the target; every other implemented delivery
    /// lives in `CasterRuntimeDelivery.swift` (issue #471).
    ///
    /// - Returns: how many timed effects were stored.
    func apply(_ spell: ResolvedSpell, caster: ActorValueHolder) -> Int {
        guard let world else { return 0 }
        let delivery = spell.data?.delivery ?? .selfTarget
        tally.note(delivery: delivery)
        guard delivery != .selfTarget else {
            return world.applyCastEffects(
                spell.record.effects,
                fromPlugin: spell.sourcePlugin,
                source: ActiveEffectSource(kind: .spell, record: spell.key),
                caster: caster.key,
                on: caster
            )
        }
        return deliverAway(spell, delivery: delivery, caster: caster, world: world)
    }

    private func notePowerSpent(_ spell: ResolvedSpell, caster: ActorValueHolder) {
        guard spell.spellType == .power, let world else { return }
        spellbook.spendPower(spell.key, onDay: world.castingGameDay, on: caster)
    }

    /// The slot one actor's hand casts in.
    func slot(_ hand: SpellHand, _ caster: ActorValueHolder) -> CastSlot {
        CastSlot(caster: caster.key, hand: hand)
    }

    /// Tallies an outcome and, for the player alone, keeps it as the readout's
    /// last line.
    @discardableResult
    func record(
        _ hand: SpellHand,
        on caster: ActorValueHolder,
        _ outcome: SpellCastOutcome
    ) -> SpellCastOutcome {
        if let failure = outcome.failure {
            tally.note(failure)
        }
        if case .ignored = outcome {
            return outcome
        }
        if caster.key == .player {
            lastOutcome[hand] = outcome
        }
        return outcome
    }
}
