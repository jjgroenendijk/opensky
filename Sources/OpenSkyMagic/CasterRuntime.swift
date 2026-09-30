// The cast loop: a hand's cast becomes spent magicka and applied effects. World
// access goes through `CasterWorld`. Fire-and-forget: `begin` charges,
// `advance` reaches ready, `release` pays and applies; magicka is checked at
// begin and release (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>).
// Concentration charges continuously and applies once per second.
// See docs/engine/spellcasting.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface
import simd

/// What a cast needs from the world it happens in. A protocol, so the shared
/// active-effect runtime is not copied. It refines `SpellHitApplying`, so a spell
/// and a projectile land through one implementation.
@MainActor
public protocol CasterWorld: SkillUseReporting, SpellHitApplying {
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

    /// Launches `payload`'s projectile from the caster along the aim ray.
    /// - Returns: false when nothing left the caster: no PROJ, a missing record, or
    ///   one the flight model cannot integrate. Counted.
    @discardableResult
    func fireSpellProjectile(_ payload: SpellPayload) -> Bool

    /// What `caster`'s aim ray reaches, for deliveries that need a target. The caster
    /// is a parameter, because NPCs cast through this runtime too.
    /// - Parameter range: SPIT's range in world units; zero means the session
    ///   maximum applies.
    func aimedSpellTarget(within range: Float, for caster: ReferenceKey) -> SpellAim
}

/// One cast in flight, identified by who is casting and in which hand.
nonisolated public struct CastSlot: Hashable, Sendable {
    public let caster: ReferenceKey
    public let hand: SpellHand
}

/// Where a caster is aiming, and what is standing there.
nonisolated public struct SpellAim: Equatable, Sendable {
    /// The actor the aim ray reached, or nil when it reached nobody.
    public let target: ReferenceKey?
    /// Where the ray ended, world space — the actor it found, or the far end of
    /// the range. What an area application measures its radius from.
    public let position: SIMD3<Float>
    /// Every actor a landed spell could catch, for the area rule.
    public let candidates: [MeleeTarget]

    public init(
        target: ReferenceKey? = nil,
        position: SIMD3<Float> = SIMD3<Float>(),
        candidates: [MeleeTarget] = []
    ) {
        self.target = target
        self.position = position
        self.candidates = candidates
    }

    /// The reading a session with no world can give.
    public static let none = SpellAim()
}

@MainActor
public final class CasterRuntime {
    /// Most whole applications one `advance` may run for a maintained cast, so
    /// a multi-second stall cannot land a minute of healing in one frame. The
    /// same cap `ActiveEffectRuntime` puts on its steps.
    public static let maximumApplicationsPerAdvance = ActiveEffectRuntime.maximumStepsPerAdvance

    public let spellbook: SpellbookRuntime
    public let values: any ActorValueAccess
    /// What the loop did and declined to do. Not `private(set)`: the ability
    /// half lives in `CasterRuntimeAbilities.swift` and a file-private setter
    /// would put it out of reach there, the same reason
    /// `ActiveEffectRuntime.tally` is internal.
    public var tally = CastingTally()
    /// The most recent outcome per hand, for a readout. The player's hands
    /// alone: an NPC's casts are reported through the combat loop's own
    /// readout, and letting every actor in a fight overwrite this would make
    /// the panel line say whatever the last skeever did.
    public private(set) var lastOutcome: [SpellHand: SpellCastOutcome] = [:]

    /// The world a cast happens in. Readable across the satellites for the
    /// reason `tally` is settable across them.
    public private(set) weak var world: (any CasterWorld)?
    /// Every cast in flight, keyed by actor and hand, so two actors charging at once
    /// do not overwrite each other. Not `private`: the concentration half lives in
    /// `CasterRuntimeConcentration.swift`.
    public var casts: [CastSlot: SpellCastState] = [:]
    /// Whether each actor's hand button was down on the previous frame, so
    /// `acceptFrame` acts on edges rather than levels. Owned here rather than in
    /// the input satellite because an extension cannot add stored properties.
    private var heldButtons: [CastSlot: Bool] = [:]

    /// The perk runtime a cost is folded through, or nil without perk data. See
    /// `CasterRuntimePerkCost.swift`.
    public var perks: (any PerkAccess)?

    public init(
        spellbook: SpellbookRuntime,
        values: any ActorValueAccess,
        world: (any CasterWorld)? = nil
    ) {
        self.spellbook = spellbook
        self.values = values
        self.world = world
    }

    public func attach(world: (any CasterWorld)?) {
        self.world = world
        casts = [:]
        heldButtons = [:]
    }

    /// Whether `caster`'s `hand` button was down on the previous frame.
    /// Internal so the input satellite can read it.
    public func wasHeld(_ hand: SpellHand, on caster: ReferenceKey = .player) -> Bool {
        heldButtons[CastSlot(caster: caster, hand: hand)] ?? false
    }

    public func setHeld(_ hand: SpellHand, _ held: Bool, on caster: ReferenceKey = .player) {
        heldButtons[CastSlot(caster: caster, hand: hand)] = held
    }

    // MARK: - Reading

    public func state(of hand: SpellHand, on caster: ReferenceKey = .player) -> SpellCastState {
        casts[CastSlot(caster: caster, hand: hand)] ?? SpellCastState()
    }

    public func phase(of hand: SpellHand, on caster: ReferenceKey = .player) -> SpellCastPhase {
        state(of: hand, on: caster).phase
    }

    /// Whether either of `caster`'s hands is mid-cast, which is what magicka
    /// regeneration stands down for.
    public func isCasting(_ caster: ReferenceKey = .player) -> Bool {
        SpellHand.allCases.contains { phase(of: $0, on: caster).isCasting }
    }

    /// Every actor with a cast in flight, in key order. What the combat panel
    /// counts so an NPC mid-charge is visible rather than assumed.
    public var castingActors: [ReferenceKey] {
        Set(casts.filter(\.value.phase.isCasting).keys.map(\.caster)).sorted()
    }

    // MARK: - Casting

    /// Starts a cast in `hand`.
    @discardableResult
    public func begin(_ hand: SpellHand, on caster: ActorValueHolder) -> SpellCastOutcome {
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
    public func release(_ hand: SpellHand, on caster: ActorValueHolder) -> SpellCastOutcome {
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
    public func cancel(_ hand: SpellHand, on caster: ActorValueHolder) {
        casts[slot(hand, caster)] = SpellCastState()
    }

    // MARK: - Advancing

    /// Runs one simulated frame of both hands.
    ///
    /// Delta 0 advances nothing, which is what a menu-paused frame delivers —
    /// the same rule regeneration and the effect tick follow.
    public func advance(delta: Float, on caster: ActorValueHolder) {
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
        let cost = cost(of: spell, caster: caster)
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
        return .concentrating(
            spell: spell.key, costPerSecond: cost(of: spell, caster: caster)
        )
    }

    /// One fire-and-forget cast: check the cost again, take it, apply the list.
    private func cast(
        _ hand: SpellHand,
        spell: ResolvedSpell,
        caster: ActorValueHolder
    ) -> SpellCastOutcome {
        let cost = cost(of: spell, caster: caster)
        let available = values.current(of: caster).magicka
        guard cost <= available else {
            casts[slot(hand, caster)] = SpellCastState()
            return .failed(.insufficientMagicka(cost: cost, available: available))
        }
        values.damage(.magicka, by: cost, on: caster)
        noteSkillUse(of: spell, amount: baseSkillUseAmount(of: spell), caster: caster)
        let stored = apply(spell, caster: caster)
        casts[slot(hand, caster)] = SpellCastState()
        notePowerSpent(spell, caster: caster)
        tally.noteCast()
        return .cast(SpellCastResult(
            magickaSpent: cost,
            entryCount: spell.record.effects.count,
            storedCount: stored
        ))
    }

    /// Delivers one application of `spell`. Self delivery applies to the caster; the
    /// other deliveries live in `CasterRuntimeDelivery.swift`.
    /// - Returns: how many timed effects were stored.
    public func apply(_ spell: ResolvedSpell, caster: ActorValueHolder) -> Int {
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
    public func slot(_ hand: SpellHand, _ caster: ActorValueHolder) -> CastSlot {
        CastSlot(caster: caster.key, hand: hand)
    }

    /// Tallies an outcome and, for the player alone, keeps it as the readout's
    /// last line.
    @discardableResult
    public func record(
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
