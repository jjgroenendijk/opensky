// The defences a landed spell meets before it reaches an actor: a held ward, spell
// absorption, and a wall between the impact and a bystander.
// See docs/engine/spell-delivery.md#defences.

import Foundation
@testable import OpenSkyActors
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import simd
import Testing

extension SpellHitTests {
    private static let ward = SpellHitApplication.wardPowerActorValue
    private static let absorbChance = SpellHitApplication.absorbChanceActorValue

    private func strike(
        _ spell: UInt32 = SpellbookFixture.Spell.firebolt,
        on holder: ActorValueHolder,
        harness: inout Harness,
        target: SpellHitTarget? = nil,
        defences: SpellHitDefences = .none,
        caster: ReferenceKey = .player,
        edit: (inout SpellPayload) -> Void = { _ in }
    ) throws -> SpellHitReport {
        var spellPayload = try payload(spell, harness: harness, caster: caster)
        edit(&spellPayload)
        let hit = SpellHit(
            payload: spellPayload,
            targets: [target ?? SpellHitTarget(key: holder.key)],
            impact: SIMD3(0, 0, 0)
        )
        return SpellHitApplication.apply(
            hit, holders: [holder.key: holder], using: &harness.effects, defences: defences
        )
    }

    /// The firebolt's 50 points go into the ward, not into health.
    @Test func aFacingWardTakesTheSpellsMagnitude() throws {
        var harness = try harness()
        let holder = Self.holder()
        harness.values.setValue(at: Self.ward, to: 60, on: holder)

        let report = try strike(on: holder, harness: &harness)

        #expect(report.wardedCount == 1)
        #expect(report.brokenWards.isEmpty)
        #expect(harness.values.current(of: holder).health == 100)
        #expect(harness.values.value(at: Self.ward, on: holder) == 10)
    }

    /// A weaker ward breaks, and the spell that broke it still does no damage.
    @Test func aWeakWardBreaksButStillBlocks() throws {
        var harness = try harness()
        let holder = Self.holder()
        harness.values.setValue(at: Self.ward, to: 20, on: holder)

        let report = try strike(on: holder, harness: &harness)

        #expect(report.brokenWards == [holder.key])
        #expect(harness.values.current(of: holder).health == 100)
        #expect(harness.values.value(at: Self.ward, on: holder) == 0)
    }

    @Test func aWardFacingAwayDoesNotBlock() throws {
        var harness = try harness()
        let holder = Self.holder()
        harness.values.setValue(at: Self.ward, to: 60, on: holder)
        var defences = SpellHitDefences()
        defences.wardFaces = { _, _ in false }

        let report = try strike(on: holder, harness: &harness, defences: defences)

        #expect(report.wardedCount == 0)
        #expect(harness.values.current(of: holder).health == 50)
    }

    /// `Mod Ward Magicka Absorption Pct` returns a share of what the ward held.
    @Test func aWardPerkGivesBackMagicka() throws {
        var harness = try harness()
        let holder = Self.holder()
        harness.values.setValue(at: Self.ward, to: 60, on: holder)
        harness.values.damage(at: SpellHitApplication.magickaActorValue, by: 50, on: holder)
        let before = harness.values.current(of: holder).magicka
        var defences = SpellHitDefences()
        defences.wardMagickaShare = { _ in 0.25 }

        _ = try strike(on: holder, harness: &harness, defences: defences)

        #expect(harness.values.current(of: holder).magicka == before + 12.5)
    }

    /// An absorbed spell does nothing and returns its base cost as magicka.
    @Test func anAbsorbedSpellRestoresItsCost() throws {
        var harness = try harness()
        let holder = Self.holder()
        harness.values.setValue(at: Self.absorbChance, to: 50, on: holder)
        harness.values.damage(at: SpellHitApplication.magickaActorValue, by: 90, on: holder)
        let before = harness.values.current(of: holder).magicka
        var defences = SpellHitDefences()
        defences.absorptionRoll = { 10 }
        var cost: Float = 0

        let report = try strike(on: holder, harness: &harness, defences: defences) {
            cost = $0.baseCost
        }

        #expect(cost > 0)
        #expect(report.absorbedCount == 1)
        #expect(harness.values.current(of: holder).health == 100)
        #expect(harness.values.current(of: holder).magicka == before + cost)
    }

    /// A roll above the chance, the SPEL "No Absorb/Reflect" flag, and a spell the
    /// target cast itself all land.
    @Test func absorptionNeedsTheRollTheFlagAndAnotherCaster() throws {
        var defences = SpellHitDefences()
        defences.absorptionRoll = { 10 }
        var missed = defences
        missed.absorptionRoll = { 90 }
        let cases = [
            AbsorbCase(defences: missed, caster: .player, disallows: false),
            AbsorbCase(defences: defences, caster: .player, disallows: true),
            AbsorbCase(defences: defences, caster: Self.victim, disallows: false)
        ]
        for item in cases {
            var harness = try harness()
            let holder = Self.holder()
            harness.values.setValue(at: Self.absorbChance, to: 50, on: holder)
            let report = try strike(
                on: holder, harness: &harness, defences: item.defences, caster: item.caster
            ) { $0.disallowsAbsorb = item.disallows }
            #expect(report.absorbedCount == 0)
        }
    }

    /// A wall keeps a fireball's area off a bystander, unless the spell ignores
    /// line of sight. The actor the projectile struck is never asked.
    @Test func aWallShieldsABystanderFromTheArea() throws {
        var defences = SpellHitDefences()
        defences.reaches = { _, _ in false }
        let bystander = SpellHitTarget(key: Self.victim, distance: 0, isDirect: false)
        let cases = [
            WallCase(target: bystander, ignores: false, blocked: 1),
            WallCase(target: bystander, ignores: true, blocked: 0),
            WallCase(target: SpellHitTarget(key: Self.victim), ignores: false, blocked: 0)
        ]
        for item in cases {
            var harness = try harness()
            let holder = Self.holder()
            let report = try strike(
                SpellbookFixture.Spell.fireball, on: holder, harness: &harness,
                target: item.target, defences: defences
            ) { $0.areaIgnoresLineOfSight = item.ignores }
            #expect(report.blockedByWallCount == item.blocked)
            #expect((harness.values.current(of: holder).health < 100) == (item.blocked == 0))
        }
    }
}

private struct AbsorbCase {
    let defences: SpellHitDefences
    let caster: ReferenceKey
    let disallows: Bool
}

private struct WallCase {
    let target: SpellHitTarget
    let ignores: Bool
    let blocked: Int
}
