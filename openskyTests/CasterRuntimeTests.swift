// The cast loop (issue #470, roadmap item 19.7): the charge, the magicka the
// cast spends, the effects it applies, and every refusal the loop reports
// rather than silently swallowing.
//
// Records are synthetic and built in code (`SpellbookFixture`) — never
// extracted game files (AGENTS.md "Legal & IP boundary").
//
// The world is a fake for the reason `FakeCombatWorld` is one: the active-effect
// runtime is a mutating value over a shared store, and what these suites need to
// know is what the cast *handed* it, entry by entry. `FakeCasterWorld` is its
// own file, shared with the delivery and panel suites.

import Foundation
@testable import opensky
import Testing

@MainActor
struct CasterRuntimeTests {
    private struct Harness {
        let runtime: CasterRuntime
        let world: FakeCasterWorld
        let spellbook: SpellbookRuntime
        let values: ActorValueRuntime
    }

    private func harness() throws -> Harness {
        let store = WorldStateStore()
        let (spellbook, _) = try SpellbookFixture.runtime(store: store)
        let values = SpellbookFixture.values(store: store)
        let world = FakeCasterWorld()
        let runtime = CasterRuntime(spellbook: spellbook, values: values)
        runtime.attach(world: world)
        return Harness(runtime: runtime, world: world, spellbook: spellbook, values: values)
    }

    /// Learns a spell and readies it, answering with its record so a suite can
    /// name the cost the store computed rather than a number nobody can check.
    @discardableResult
    private func ready(
        _ objectID: UInt32,
        in hand: SpellHand,
        _ harness: Harness
    ) throws -> ResolvedSpell {
        let key = SpellbookFixture.key(objectID)
        harness.spellbook.learn(key, on: .player)
        try harness.spellbook.equip(key, in: hand, on: .player)
        return try #require(harness.spellbook.record(key))
    }

    // MARK: - Fire and forget

    /// The acceptance picture: a healing spell readied to a hand, cast with
    /// magicka deducted and the effect list applied to the caster.
    @Test func castingSpendsMagickaAndAppliesTheEffectListToTheCaster() throws {
        let harness = try harness()
        let spell = try ready(SpellbookFixture.Spell.fastHealing, in: .right, harness)
        #expect(spell.cost.cost > 0)

        #expect(harness.runtime.begin(.right, on: .player).failure == nil)
        #expect(harness.runtime.phase(of: .right) == .charging)
        harness.runtime.advance(delta: 0.5, on: .player)
        #expect(harness.runtime.phase(of: .right) == .ready)

        let outcome = harness.runtime.release(.right, on: .player)

        #expect(outcome.isCast)
        #expect(harness.values.current(of: .player).magicka == 100 - Float(spell.cost.cost))
        #expect(harness.world.applications.count == 1)
        #expect(harness.world.applications[0].target == ReferenceKey.player)
        #expect(harness.world.applications[0].source.kind == .spell)
        #expect(harness.runtime.phase(of: .right) == .idle)
        #expect(harness.runtime.tally.castCount == 1)
    }

    /// A spell with no charge time reaches the release window on the same call
    /// that started it.
    @Test func aSpellWithNoChargeTimeIsReadyImmediately() throws {
        let harness = try harness()
        try ready(SpellbookFixture.Spell.masterHeal, in: .right, harness)

        harness.runtime.begin(.right, on: .player)

        #expect(harness.runtime.phase(of: .right) == .ready)
    }

    /// Releasing inside the charge casts nothing and spends nothing.
    @Test func releasingBeforeTheChargeFinishesCastsNothing() throws {
        let harness = try harness()
        try ready(SpellbookFixture.Spell.fastHealing, in: .right, harness)
        harness.runtime.begin(.right, on: .player)
        harness.runtime.advance(delta: 0.2, on: .player)

        let outcome = harness.runtime.release(.right, on: .player)

        #expect(outcome.failure == .notCharged(remaining: 0.3))
        #expect(harness.values.current(of: .player).magicka == 100)
        #expect(harness.world.applications.isEmpty)
    }

    /// UESP: "Attempting to cast a spell with a cost higher than your available
    /// magicka will result in the failure of the attempted casting."
    @Test func aCastIsRefusedWhenMagickaIsShortOfTheCost() throws {
        let harness = try harness()
        let spell = try ready(SpellbookFixture.Spell.fastHealing, in: .right, harness)
        harness.values.set(.magicka, to: Float(spell.cost.cost) - 1, on: .player)

        let outcome = harness.runtime.begin(.right, on: .player)

        #expect(outcome.failure != nil)
        if case let .insufficientMagicka(cost, available) = outcome.failure {
            #expect(cost == Float(spell.cost.cost))
            #expect(available == Float(spell.cost.cost) - 1)
        } else {
            Issue.record("expected an insufficient-magicka refusal")
        }
        #expect(harness.world.applications.isEmpty)
        #expect(harness.runtime.tally.failureCount == 1)
    }

    /// Magicka can fall inside the charge, so the check runs at both ends.
    @Test func magickaLostDuringTheChargeStillRefusesTheCast() throws {
        let harness = try harness()
        let spell = try ready(SpellbookFixture.Spell.fastHealing, in: .right, harness)
        harness.runtime.begin(.right, on: .player)
        harness.runtime.advance(delta: 0.5, on: .player)
        harness.values.set(.magicka, to: Float(spell.cost.cost) - 1, on: .player)

        let outcome = harness.runtime.release(.right, on: .player)

        #expect(outcome.failure != nil)
        #expect(harness.world.applications.isEmpty)
    }

    @Test func castingWithNoSpellReadiedIsRefusedWithTheHandNamed() throws {
        let harness = try harness()

        #expect(harness.runtime.begin(.left, on: .player).failure == .noSpellReadied(.left))
    }

    /// Touch delivery needs the melee-reach geometry and the contact frame the
    /// animation graph owns, so item 19.8 counts it rather than approximating
    /// it as a zero-range aimed cast.
    @Test func anUnimplementedDeliveryIsRefusedAndCounted() throws {
        let harness = try harness()
        try ready(SpellbookFixture.Spell.touchOfDeath, in: .right, harness)

        let outcome = harness.runtime.begin(.right, on: .player)

        #expect(outcome.failure == .deliveryUnsupported(.touch))
        #expect(harness.runtime.tally.failureCount == 1)
    }

    // MARK: - Concentration

    /// Cost drains continuously and the effect list lands once on entry and
    /// once per whole second after that.
    @Test func aMaintainedCastDrainsPerSecondAndAppliesEachSecond() throws {
        let harness = try harness()
        let spell = try ready(SpellbookFixture.Spell.healing, in: .right, harness)
        let perSecond = Float(spell.cost.cost)

        harness.runtime.begin(.right, on: .player)
        #expect(harness.runtime.phase(of: .right) == .concentrating)
        // The first application is on entry, so a heal starts healing when it
        // starts costing.
        #expect(harness.world.applications.count == 1)

        for _ in 0 ..< 120 {
            harness.runtime.advance(delta: 1.0 / 60, on: .player)
        }

        #expect(harness.runtime.phase(of: .right) == .concentrating)
        #expect(harness.world.applications.count == 3)
        let spent = 100 - harness.values.current(of: .player).magicka
        #expect(abs(spent - perSecond * 2) < 0.05)
        #expect(harness.runtime.tally.concentrationSeconds == 3)
    }

    /// UESP: "Concentration spells do not have a set duration. Rather, the
    /// duration is determined by how long you hold the casting trigger."
    @Test func releasingAMaintainedCastStopsBothTheDrainAndTheEffects() throws {
        let harness = try harness()
        try ready(SpellbookFixture.Spell.healing, in: .right, harness)
        harness.runtime.begin(.right, on: .player)
        for _ in 0 ..< 60 {
            harness.runtime.advance(delta: 1.0 / 60, on: .player)
        }
        let spentWhileHeld = 100 - harness.values.current(of: .player).magicka
        let applied = harness.world.applications.count

        let outcome = harness.runtime.release(.right, on: .player)
        harness.runtime.advance(delta: 1, on: .player)

        if case let .released(_, held, _) = outcome {
            // Sixty 1/60 s steps sum to slightly under a second, which is the
            // arithmetic `SpellCastState.secondTolerance` exists for.
            #expect(held > 1 - SpellCastState.secondTolerance)
        } else {
            Issue.record("expected a released outcome, got \(outcome)")
        }
        #expect(harness.runtime.phase(of: .right) == .idle)
        #expect(harness.world.applications.count == applied)
        #expect(100 - harness.values.current(of: .player).magicka == spentWhileHeld)
    }

    /// The SPIT cast duration is the floor: a release inside it keeps the cast
    /// running until it elapses.
    @Test func aReleaseInsideTheMinimumDurationKeepsTheCastRunning() throws {
        let harness = try harness()
        try ready(SpellbookFixture.Spell.healing, in: .right, harness)
        harness.runtime.begin(.right, on: .player)

        harness.runtime.release(.right, on: .player)

        #expect(harness.runtime.phase(of: .right) == .concentrating)
        harness.runtime.advance(delta: 0.5, on: .player)
        #expect(harness.runtime.phase(of: .right) == .idle)
    }

    /// The same refusal ends a cast already running, because the cost keeps
    /// being charged for as long as it is maintained.
    @Test func aMaintainedCastEndsWhenTheMagickaRunsOut() throws {
        let harness = try harness()
        let spell = try ready(SpellbookFixture.Spell.healing, in: .right, harness)
        harness.values.set(.magicka, to: Float(spell.cost.cost), on: .player)
        harness.runtime.begin(.right, on: .player)

        for _ in 0 ..< 120 {
            harness.runtime.advance(delta: 1.0 / 60, on: .player)
        }

        #expect(harness.runtime.phase(of: .right) == .idle)
        #expect(harness.values.current(of: .player).magicka == 0)
        #expect(harness.runtime.tally.failureCount >= 1)
    }

    // MARK: - Powers and abilities

    /// UESP: "Each Greater Power can only be used once per game day."
    @Test func aGreaterPowerIsRefusedASecondTimeOnTheSameDay() throws {
        let harness = try harness()
        let power = SpellbookFixture.key(SpellbookFixture.Spell.dragonskin)
        harness.spellbook.learn(power, on: .player)
        // A power takes no hand, so it is written straight into one for this
        // suite: the voice slot 19.4 left out of scope is what would carry it.
        harness.runtime.spellbook.store.set(
            SpellbookState(known: [power], rightHand: power),
            for: .player,
            in: nil
        )

        #expect(harness.runtime.begin(.right, on: .player).failure == nil)
        harness.runtime.release(.right, on: .player)
        #expect(harness.spellbook.state(of: .player).hasSpentPower(power, onDay: 0))

        let second = harness.runtime.begin(.right, on: .player)
        #expect(second.failure == .powerAlreadyUsedToday(day: 0))

        harness.world.castingGameDay = 1
        #expect(harness.runtime.begin(.right, on: .player).failure == nil)
    }

    /// An ability is carried, not cast.
    @Test func anAbilityCannotBeCastFromAHand() throws {
        let harness = try harness()
        let ability = SpellbookFixture.key(SpellbookFixture.Spell.resistFire)
        harness.runtime.spellbook.store.set(
            SpellbookState(known: [ability], rightHand: ability),
            for: .player,
            in: nil
        )

        #expect(harness.runtime.begin(.right, on: .player).failure == .abilityNotCastable)
    }

    /// A zero-duration ability entry is counted rather than applied wrongly:
    /// the active-effect runtime has no permanent mode, and applying one once
    /// would be a nudge wearing the name of a permanent bonus.
    @Test func abilitiesApplyTheirTimedEntriesAndCountTheRest() throws {
        let harness = try harness()
        harness.spellbook.learn(
            SpellbookFixture.key(SpellbookFixture.Spell.resistFire),
            on: .player
        )

        let stored = harness.runtime.applyAbilities(on: .player)

        #expect(stored == 1)
        #expect(harness.world.applications.count == 1)
        #expect(harness.world.applications[0].entries == 1)
        #expect(harness.runtime.tally.unheldAbilityEntries == 1)
    }

    // MARK: - Input

    /// The button edges, not its level: a held button must not restart the
    /// charge on every frame.
    @Test func aHeldButtonBeginsOnceAndReleasesOnce() throws {
        let harness = try harness()
        try ready(SpellbookFixture.Spell.fastHealing, in: .right, harness)

        for _ in 0 ..< 60 {
            harness.runtime.acceptFrame(
                CastingIntent(rightHeld: true, deltaTime: 1.0 / 60),
                on: .player
            )
        }
        #expect(harness.runtime.phase(of: .right) == .ready)
        #expect(harness.runtime.tally.castCount == 0)

        harness.runtime.acceptFrame(
            CastingIntent(rightHeld: false, deltaTime: 1.0 / 60),
            on: .player
        )

        #expect(harness.runtime.tally.castCount == 1)
        #expect(harness.runtime.phase(of: .right) == .idle)
    }

    /// A hand holding no spell is left alone entirely, which is what leaves its
    /// button to melee.
    @Test func anEmptyHandIgnoresItsButton() throws {
        let harness = try harness()

        harness.runtime.acceptFrame(
            CastingIntent(leftHeld: true, rightHeld: true, deltaTime: 1.0 / 60),
            on: .player
        )

        #expect(harness.runtime.phase(of: .left) == .idle)
        #expect(harness.runtime.phase(of: .right) == .idle)
        #expect(harness.runtime.tally.failureCount == 0)
    }
}
