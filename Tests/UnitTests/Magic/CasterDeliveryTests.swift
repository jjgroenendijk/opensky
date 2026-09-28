// Casting at something other than yourself (issue #471, roadmap item 19.8):
// which delivery does what, what leaves the caster, and the concentration
// cadence an aimed beam applies on.
//
// Records are synthetic and built in code (`SpellbookFixture`) — never
// extracted game files (AGENTS.md "Legal & IP boundary").
//
// The world is `FakeCasterWorld`, for the reason the cast-loop suite uses one:
// what these tests need to know is what the delivery *handed* the world — which
// payload, aimed at whom, how often — and not what a real session then did with
// it. `SpellHitTests` asks the second question against a real effect runtime.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct CasterDeliveryTests {
    private struct Harness {
        let runtime: CasterRuntime
        let world: FakeCasterWorld
        let spellbook: SpellbookRuntime
        let values: ActorValueRuntime
    }

    private static let victim = ReferenceKey.plugin(name: "base.esm", objectID: 0x0900)

    private func harness() throws -> Harness {
        let store = WorldStateStore()
        let (spellbook, _) = try SpellbookFixture.runtime(store: store)
        let values = SpellbookFixture.values(store: store)
        let world = FakeCasterWorld()
        let runtime = CasterRuntime(spellbook: spellbook, values: values)
        runtime.attach(world: world)
        return Harness(runtime: runtime, world: world, spellbook: spellbook, values: values)
    }

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

    /// Charges and releases one fire-and-forget cast in one call.
    @discardableResult
    private func cast(_ objectID: UInt32, _ harness: Harness) throws -> SpellCastOutcome {
        try ready(objectID, in: .right, harness)
        harness.runtime.begin(.right, on: .player)
        harness.runtime.advance(delta: 1, on: .player)
        return harness.runtime.release(.right, on: .player)
    }

    private func aim(at target: ReferenceKey?) -> SpellAim {
        SpellAim(
            target: target,
            position: SIMD3(500, 0, 0),
            candidates: target.map { [MeleeTarget(key: $0, feet: SIMD3(500, 0, 0))] } ?? []
        )
    }

    // MARK: - Aimed, fire and forget

    /// The acceptance shape: an aimed destruction spell spends its magicka and
    /// puts a projectile in the air rather than applying anything to the caster.
    @Test func anAimedCastFiresTheProjectileAndAppliesNothingToTheCaster() throws {
        let harness = try harness()
        let spell = try #require(harness.spellbook.record(
            SpellbookFixture.key(SpellbookFixture.Spell.firebolt)
        ))

        let outcome = try cast(SpellbookFixture.Spell.firebolt, harness)

        #expect(outcome.isCast)
        #expect(harness.values.current(of: .player).magicka == 100 - Float(spell.cost.cost))
        #expect(harness.world.applications.isEmpty)
        #expect(harness.world.firedProjectiles.count == 1)
        #expect(harness.runtime.tally.projectileCount == 1)
        #expect(harness.runtime.tally.deliveryCounts["aimed"] == 1)
    }

    /// The payload a projectile carries is resolved at cast time: the spell's
    /// own effect list, its plugin, the caster, the PROJ its MGEF names, and
    /// whether it is hostile.
    @Test func theLaunchedPayloadCarriesEverythingResolvedAtCastTime() throws {
        let harness = try harness()

        try cast(SpellbookFixture.Spell.firebolt, harness)

        let payload = try #require(harness.world.firedProjectiles.first)
        #expect(payload.caster == .player)
        #expect(payload.spell == SpellbookFixture.key(SpellbookFixture.Spell.firebolt))
        #expect(payload.entries.count == 1)
        #expect(payload.entries.first?.magnitude == 50)
        #expect(payload.isHostile)
        #expect(!payload.ignoresResistance)
        #expect(payload.projectile == FormID(SpellbookFixture.fireBoltProjectile))
        #expect(payload.name == "Firebolt")
    }

    /// A healing spell is not hostile, so nothing a landed one does should
    /// start a fight. The flag the combat loop reads is resolved here.
    @Test func aRestorativePayloadIsNotHostile() throws {
        let harness = try harness()
        let spell = try #require(harness.spellbook.record(
            SpellbookFixture.key(SpellbookFixture.Spell.fastHealing)
        ))

        #expect(!spell.payload(caster: .player).isHostile)
    }

    /// The "Ignore Resistance" flag travels with the payload rather than being
    /// re-read at impact, so a projectile applies the spell that was cast.
    @Test func theIgnoreResistanceFlagTravelsWithThePayload() throws {
        let harness = try harness()

        try cast(SpellbookFixture.Spell.unresistedBolt, harness)

        #expect(harness.world.firedProjectiles.first?.ignoresResistance == true)
    }

    /// A projectile that could not be launched — no PROJ this load order
    /// resolves — is counted rather than silently succeeding.
    @Test func aProjectileThatCouldNotLaunchIsNotCounted() throws {
        let harness = try harness()
        harness.world.canFireProjectile = false

        let outcome = try cast(SpellbookFixture.Spell.firebolt, harness)

        #expect(outcome.isCast)
        #expect(harness.runtime.tally.projectileCount == 0)
        #expect(harness.runtime.tally.deliveryCounts["aimed"] == 1)
    }

    // MARK: - Target actor

    /// Target-actor delivery applies straight to whatever the aim ray reaches,
    /// within the SPIT range the record carries.
    @Test func targetActorDeliveryAppliesToTheAimedActorWithinRange() throws {
        let harness = try harness()
        harness.world.aim = aim(at: Self.victim)

        try cast(SpellbookFixture.Spell.sparkAtTarget, harness)

        #expect(harness.world.aimRanges == [1500])
        let hit = try #require(harness.world.spellHits.first)
        #expect(hit.targets.map(\.key) == [Self.victim])
        #expect(hit.targets.first?.isDirect == true)
        #expect(harness.world.firedProjectiles.isEmpty)
        #expect(harness.runtime.tally.deliveryCounts["target actor"] == 1)
    }

    /// A ray that reaches nobody applies nothing, and that is ordinary play
    /// rather than a refusal: the magicka is still spent.
    @Test func aimingAtNobodyAppliesNothingAndStillCosts() throws {
        let harness = try harness()
        harness.world.aim = aim(at: nil)
        let spell = try #require(harness.spellbook.record(
            SpellbookFixture.key(SpellbookFixture.Spell.sparkAtTarget)
        ))

        try cast(SpellbookFixture.Spell.sparkAtTarget, harness)

        #expect(harness.world.spellHits.isEmpty)
        #expect(harness.values.current(of: .player).magicka == 100 - Float(spell.cost.cost))
    }

    // MARK: - Concentration

    /// The flamethrower shape: an aimed concentration spell applies to whatever
    /// the ray reaches, on the same cadence a maintained self cast runs — once
    /// on entry, once per whole second held.
    @Test func anAimedConcentrationCastAppliesOnEveryWholeSecond() throws {
        let harness = try harness()
        harness.world.aim = aim(at: Self.victim)
        try ready(SpellbookFixture.Spell.flamestream, in: .right, harness)

        harness.runtime.begin(.right, on: .player)
        #expect(harness.runtime.phase(of: .right) == .concentrating)
        #expect(harness.world.spellHits.count == 1)

        for _ in 0 ..< 120 {
            harness.runtime.advance(delta: 1.0 / 60, on: .player)
        }

        #expect(harness.world.spellHits.count == 3)
        #expect(harness.world.spellHits.allSatisfy { $0.targets.map(\.key) == [Self.victim] })
        #expect(harness.runtime.tally.concentrationSeconds == 3)
    }

    /// The ray is resampled on every application, so sweeping a beam off a
    /// target stops applying to it while the cast keeps running.
    @Test func sweepingTheBeamOffATargetStopsApplyingToIt() throws {
        let harness = try harness()
        harness.world.aim = aim(at: Self.victim)
        try ready(SpellbookFixture.Spell.flamestream, in: .right, harness)
        harness.runtime.begin(.right, on: .player)

        harness.world.aim = aim(at: nil)
        for _ in 0 ..< 120 {
            harness.runtime.advance(delta: 1.0 / 60, on: .player)
        }

        #expect(harness.world.spellHits.count == 1)
        #expect(harness.runtime.phase(of: .right) == .concentrating)
    }

    // MARK: - Coverage

    /// Every delivery this build refuses, refused for the reason the record
    /// gives rather than silently doing something else.
    @Test func touchAndTargetLocationAreCountedRatherThanCarriedOut() {
        #expect(!SpellDelivery.isImplemented(.touch, castingType: .fireAndForget))
        #expect(!SpellDelivery.isImplemented(.targetLocation, castingType: .fireAndForget))
        #expect(!SpellDelivery.isImplemented(.unknown(raw: 9), castingType: .fireAndForget))
        // Target-actor concentration needs a tracked target this build has no
        // AI targeting for (issue 19.10), so only its fire-and-forget half runs.
        #expect(SpellDelivery.isImplemented(.targetActor, castingType: .fireAndForget))
        #expect(!SpellDelivery.isImplemented(.targetActor, castingType: .concentration))
        #expect(SpellDelivery.isImplemented(.aimed, castingType: .concentration))
        #expect(SpellDelivery.isImplemented(.selfTarget, castingType: nil))
    }

    /// The PROJ an MGEF names resolves through the same item index the arrow
    /// path reads, and its speed, gravity and range come from the record rather
    /// than from a default (scope point 1).
    @Test func theProjectileProfileComesFromThePROJTheEffectNames() throws {
        let items = try SpellbookFixture.projectileStore()

        let profile = try #require(
            items.projectileProfile(FormID(SpellbookFixture.fireBoltProjectile))
        )

        #expect(profile.speed == 3000)
        #expect(profile.gravityFactor == 0)
        #expect(profile.range == 4000)
        #expect(profile.isFlyable)
    }
}
