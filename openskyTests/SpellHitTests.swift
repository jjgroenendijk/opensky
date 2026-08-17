// Applying a landed spell (issue #471, roadmap item 19.8): the resistance
// scaling, the area rule, and what reaches whom.
//
// Records are synthetic and built in code (`SpellbookFixture`) — never
// extracted game files (AGENTS.md "Legal & IP boundary").
//
// The effect runtime here is a real one over a real `WorldStateStore`, unlike
// the cast-loop suites' fake: the question this file asks is what the *actor
// value* ended up at after a resistance-scaled application, and a fake world
// could only answer what it was handed.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct SpellHitTests {
    private struct Harness {
        var effects: ActiveEffectRuntime
        let values: ActorValueRuntime
        let spellbook: SpellbookRuntime
    }

    private static let victim = ReferenceKey.plugin(name: "base.esm", objectID: 0x0900)

    private func harness() throws -> Harness {
        let store = WorldStateStore()
        let (spellbook, _) = try SpellbookFixture.runtime(store: store)
        let values = SpellbookFixture.values(store: store)
        let effects = try SpellbookFixture.effectStore(index: SpellbookFixture.index())
        return Harness(
            effects: ActiveEffectRuntime(values: values, effects: effects),
            values: values,
            spellbook: spellbook
        )
    }

    /// A non-player actor, so the 85% player cap does not enter the arithmetic
    /// unless a test asks for it.
    private static func holder(_ key: ReferenceKey = victim) -> ActorValueHolder {
        ActorValueHolder(key: key, subject: .actor(base: FormID(0x0000_0F01)), cell: nil)
    }

    private func payload(
        _ objectID: UInt32,
        harness: Harness,
        caster: ReferenceKey = .player
    ) throws -> SpellPayload {
        let spell = try #require(harness.spellbook.record(SpellbookFixture.key(objectID)))
        return spell.payload(caster: caster)
    }

    private func hit(
        _ payload: SpellPayload,
        targets: [SpellHitTarget],
        position: SIMD3<Float> = SIMD3()
    ) -> SpellHit {
        SpellHit(payload: payload, position: position, targets: targets)
    }

    // MARK: - Resistance scaling

    /// The acceptance arithmetic: a hostile fire effect of magnitude 50 against
    /// 40% Resist Fire lands 30 points of damage, and the adjustment says so.
    @Test func aHostileEffectIsScaledByTheTargetsResistance() throws {
        var harness = try harness()
        let holder = Self.holder()
        harness.values.setValue(at: ActorValueIndex.resistFire, to: 40, on: holder)
        let payload = try payload(SpellbookFixture.Spell.firebolt, harness: harness)

        let report = SpellHitApplication.apply(
            hit(payload, targets: [SpellHitTarget(key: holder.key)]),
            holders: [holder.key: holder],
            using: &harness.effects
        )

        let adjustment = try #require(report.adjustments.first)
        #expect(abs(adjustment.multiplier - 0.6) < 0.0001)
        #expect(adjustment.baseMagnitude == 50)
        #expect(abs(adjustment.adjustedMagnitude - 30) < 0.001)
        #expect(adjustment.resistance == ActorValueIndex.resistFire)
        #expect(abs(harness.values.current(of: holder).health - 70) < 0.001)
    }

    /// UESP's own composition rule, applied through a cast: Resist Magic first,
    /// then the element (<https://en.uesp.net/wiki/Skyrim:Resist_Magic>).
    @Test func resistMagicComposesWithTheElementalResistance() throws {
        var harness = try harness()
        let holder = Self.holder()
        harness.values.setValue(at: ActorValueIndex.resistMagic, to: 50, on: holder)
        harness.values.setValue(at: ActorValueIndex.resistFire, to: 50, on: holder)
        let payload = try payload(SpellbookFixture.Spell.firebolt, harness: harness)

        let report = SpellHitApplication.apply(
            hit(payload, targets: [SpellHitTarget(key: holder.key)]),
            holders: [holder.key: holder],
            using: &harness.effects
        )

        #expect(report.adjustments.first?.multiplier == 0.25)
        #expect(harness.values.current(of: holder).health == 87.5)
    }

    /// A negative resistance is a weakness and multiplies damage up, which is
    /// what "Target is <mag>% weaker to fire damage" means
    /// (<https://en.uesp.net/wiki/Skyrim:Weakness_to_Fire>).
    @Test func aWeaknessIncreasesTheMagnitude() throws {
        var harness = try harness()
        let holder = Self.holder()
        harness.values.setValue(at: ActorValueIndex.resistFire, to: -50, on: holder)
        let payload = try payload(SpellbookFixture.Spell.firebolt, harness: harness)

        let report = SpellHitApplication.apply(
            hit(payload, targets: [SpellHitTarget(key: holder.key)]),
            holders: [holder.key: holder],
            using: &harness.effects
        )

        #expect(report.adjustments.first?.multiplier == 1.5)
        #expect(harness.values.current(of: holder).health == 25)
    }

    /// The 85% cap is the player's alone, so a fully resistant NPC is immune
    /// and takes nothing at all.
    @Test func aFullyResistantNonPlayerIsImmune() throws {
        var harness = try harness()
        let holder = Self.holder()
        harness.values.setValue(at: ActorValueIndex.resistFire, to: 100, on: holder)
        let payload = try payload(SpellbookFixture.Spell.firebolt, harness: harness)

        SpellHitApplication.apply(
            hit(payload, targets: [SpellHitTarget(key: holder.key)]),
            holders: [holder.key: holder],
            using: &harness.effects
        )

        #expect(harness.values.current(of: holder).health == 100)
    }

    /// The player's own resistance stops at 85%, so the same 100 points leaves
    /// 15% of the damage getting through.
    @Test func thePlayerCapLeavesFifteenPercentComingThrough() throws {
        var harness = try harness()
        harness.values.setValue(at: ActorValueIndex.resistFire, to: 100, on: .player)
        let payload = try payload(SpellbookFixture.Spell.firebolt, harness: harness)

        let report = SpellHitApplication.apply(
            hit(payload, targets: [SpellHitTarget(key: .player)]),
            holders: [.player: .player],
            using: &harness.effects
        )

        #expect(abs((report.adjustments.first?.multiplier ?? 0) - 0.15) < 0.0001)
        #expect(abs(harness.values.current(of: .player).health - 92.5) < 0.001)
    }

    /// A restorative effect is not hostile, so nothing scales it and the
    /// adjustment list stays empty — a healing spell is not resisted.
    @Test func aNonHostileEffectIsNotScaled() throws {
        var harness = try harness()
        let holder = Self.holder()
        harness.values.setValue(at: ActorValueIndex.resistMagic, to: 80, on: holder)
        harness.values.damage(.health, by: 50, on: holder)
        let payload = try payload(SpellbookFixture.Spell.fastHealing, harness: harness)

        let report = SpellHitApplication.apply(
            hit(payload, targets: [SpellHitTarget(key: holder.key)]),
            holders: [holder.key: holder],
            using: &harness.effects
        )

        #expect(report.adjustments.isEmpty)
        #expect(harness.values.current(of: holder).health == 70)
    }

    /// The SPEL "Ignore Resistance" flag skips the step entirely, even against
    /// an otherwise immune target.
    @Test func theIgnoreResistanceFlagSkipsScaling() throws {
        var harness = try harness()
        let holder = Self.holder()
        harness.values.setValue(at: ActorValueIndex.resistFire, to: 100, on: holder)
        let payload = try payload(SpellbookFixture.Spell.unresistedBolt, harness: harness)

        let report = SpellHitApplication.apply(
            hit(payload, targets: [SpellHitTarget(key: holder.key)]),
            holders: [holder.key: holder],
            using: &harness.effects
        )

        #expect(report.adjustments.isEmpty)
        #expect(harness.values.current(of: holder).health == 50)
    }

    // MARK: - Area

    /// A bystander receives only the entries whose area reaches it, and the
    /// struck actor receives every entry — which is the shape vanilla
    /// `Fireball` is authored in: an area damage entry beside a point stagger.
    @Test func onlyAreaEntriesReachABystander() throws {
        let harness = try harness()
        let payload = try payload(SpellbookFixture.Spell.fireball, harness: harness)
        let radius = MagicAreaSettings.documentedDefaults.radius(ofArea: 15)

        let direct = SpellHitApplication.entries(
            of: payload, reaching: SpellHitTarget(key: Self.victim)
        )
        let near = SpellHitApplication.entries(
            of: payload,
            reaching: SpellHitTarget(key: Self.victim, distance: radius - 1, isDirect: false)
        )
        let far = SpellHitApplication.entries(
            of: payload,
            reaching: SpellHitTarget(key: Self.victim, distance: radius + 1, isDirect: false)
        )

        #expect(direct.count == 2)
        #expect(near.count == 1)
        #expect(near.first?.area == 15)
        #expect(far.isEmpty)
    }

    /// An EFIT area of 15 is 15 feet, and a foot is more than one world unit —
    /// the measurement the file comment records, pinned so a later change to
    /// the conversion is a deliberate one.
    @Test func anAreaIsConvertedOutOfFeetIntoWorldUnits() {
        let settings = MagicAreaSettings.documentedDefaults
        #expect(settings.radius(ofArea: 0) == 0)
        #expect(settings.radius(ofArea: 15) > 300)
        #expect(settings.radius(ofArea: 15) == 15 * settings.worldUnitsPerAreaUnit)
    }

    /// Who a landed spell reaches: the struck actor first and direct, then
    /// bystanders inside the widest radius by distance, and never the caster.
    @Test func targetingOrdersBystandersByDistanceAndSkipsTheCaster() throws {
        let harness = try harness()
        let payload = try payload(SpellbookFixture.Spell.fireball, harness: harness)
        let radius = MagicAreaSettings.documentedDefaults.radius(ofArea: 15)
        let struck = ReferenceKey.plugin(name: "base.esm", objectID: 0x0901)
        let near = ReferenceKey.plugin(name: "base.esm", objectID: 0x0902)
        let candidates = [
            MeleeTarget(key: struck, feet: SIMD3()),
            MeleeTarget(key: near, feet: SIMD3(radius * 0.5, 0, 0)),
            MeleeTarget(key: .player, feet: SIMD3(radius * 0.25, 0, 0)),
            MeleeTarget(key: Self.victim, feet: SIMD3(radius * 4, 0, 0))
        ]

        let targets = SpellHitTargeting.targets(
            of: payload,
            at: SIMD3(),
            struck: struck,
            candidates: candidates,
            excluding: .player
        )

        #expect(targets.map(\.key) == [struck, near])
        #expect(targets[0].isDirect)
        #expect(!targets[1].isDirect)
        #expect(targets[1].distance > 0)
    }

    /// A point spell that struck geometry reaches nobody, which is what an
    /// area of zero against a wall means.
    @Test func aPointSpellThatHitGeometryReachesNobody() throws {
        let harness = try harness()
        let payload = try payload(SpellbookFixture.Spell.firebolt, harness: harness)

        let targets = SpellHitTargeting.targets(
            of: payload,
            at: SIMD3(),
            struck: nil,
            candidates: [MeleeTarget(key: Self.victim, feet: SIMD3(10, 0, 0))],
            excluding: .player
        )

        #expect(targets.isEmpty)
    }

    /// An actor whose holder the session can no longer resolve is skipped
    /// rather than guessed at — a target evicted between the impact and the
    /// application.
    @Test func aTargetWithNoHolderIsSkipped() throws {
        var harness = try harness()
        let payload = try payload(SpellbookFixture.Spell.firebolt, harness: harness)

        let report = SpellHitApplication.apply(
            hit(payload, targets: [SpellHitTarget(key: Self.victim)]),
            holders: [:],
            using: &harness.effects
        )

        #expect(report.targetCount == 0)
        #expect(!report.didApply)
    }
}
