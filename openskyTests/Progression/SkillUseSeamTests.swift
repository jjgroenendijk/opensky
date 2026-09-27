// The seams skill use was wired into (issue #498, roadmap item 20.5): a swing,
// a blow taken, an arrow and a cast.
//
// Each test drives the simulating runtime and asserts what reached the
// `SkillUseReporting` seam, rather than what progression made of it: a runtime
// that stops reporting fails here even when the conversion is still right, and
// `SkillAdvancementRuntimeTests` is the other half.
//
// Records are synthetic and built in code — never extracted game files
// (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct SkillUseSeamTests {
    private static let drawEvents = [
        CombatGraphNames.weaponDraw,
        CombatGraphNames.beginWeaponDraw
    ]

    private static func swing(_ runtime: MeleeCombatRuntime) {
        runtime.handleGraphEvents(drawEvents)
        runtime.acceptFrame(MeleeIntent(attack: true))
        runtime.handleGraphEvents([
            CombatGraphNames.attackStart,
            CombatGraphNames.preHitFrame,
            CombatGraphNames.hitFrame
        ])
    }

    // MARK: - Melee

    /// A landed swing reports the weapon's *base* damage against the weapon's
    /// own skill, and the struck actor's armour against its raw rating.
    @Test func aSwingReportsTheWeaponSkillAndTheTargetsArmour() {
        let world = FakeMeleeWorld()
        world.targets = [MeleeTarget(key: .generated(1), feet: SIMD3(80, 0, 0))]
        let runtime = MeleeCombatRuntime(settings: .synthetic, world: world)
        runtime.weapon = MeleeWeaponProfile(damage: 24, reach: 1, handType: .greatsword)

        Self.swing(runtime)

        #expect(world.skillUses.count == 2)
        #expect(world.skillUses.first?.actor == world.attacker.key)
        #expect(world.skillUses.first?.action == .weaponHit(.greatsword))
        #expect(world.skillUses.first?.amount == 24)
        #expect(world.skillUses.last?.actor == .generated(1))
        #expect(world.skillUses.last?.action == .armorHit)
        #expect(world.skillUses.last?.amount == 24)
    }

    /// A fortify effect raises the damage dealt but not what the swing teaches:
    /// "Boosting weapon damage via skill perks or equipment enchantments does
    /// not result in more XP per strike."
    @Test func aFortifiedSwingStillReportsTheBaseWeaponDamage() {
        let world = FakeMeleeWorld()
        world.targets = [MeleeTarget(key: .generated(1), feet: SIMD3(80, 0, 0))]
        world.attackMultiplier = 2
        let runtime = MeleeCombatRuntime(settings: .synthetic, world: world)
        runtime.weapon = MeleeWeaponProfile(damage: 10, reach: 1, handType: .sword)

        Self.swing(runtime)

        #expect(world.damage[.generated(1)] == 20)
        #expect(world.skillUses.first?.amount == 10)
        // The armour half is the raw rating of the strike, which the fortify
        // term is part of.
        #expect(world.skillUses.last?.amount == 20)
    }

    /// A blocked blow reports Block for the raw damage the block absorbed,
    /// beside the two uses an unblocked one reports.
    @Test func aBlockedBlowReportsBlock() throws {
        let world = FakeMeleeWorld()
        world.targets = [MeleeTarget(key: .generated(1), feet: SIMD3(80, 0, 0))]
        world.blocks[.generated(1)] = .weapon
        let runtime = MeleeCombatRuntime(settings: .synthetic, world: world)
        runtime.weapon = MeleeWeaponProfile(damage: 10, reach: 1, handType: .sword)

        Self.swing(runtime)

        let blocked = try #require(world.skillUses.first { $0.action == .blockedBlow })
        let fraction = try #require(runtime.trace.last?.damage.blockedFraction)
        #expect(blocked.actor == .generated(1))
        #expect(abs(blocked.amount - 10 * fraction) < 0.0001)
        #expect(fraction > 0)
    }

    // MARK: - The other direction

    /// An NPC's blow on the player reports the same three uses, with the
    /// player on the receiving two.
    @Test func anNPCsBlowReportsThePlayersDefensiveSkills() {
        let (runtime, world) = CombatLoopFixture.session(blockChance: 1)
        world.blocks[.player] = .weapon
        CombatLoopFixture.engage(runtime, world)

        CombatLoopFixture.run(runtime, seconds: CombatLoopFixture.cycleSeconds)

        let opponent = CombatLoopFixture.opponent
        #expect(world.skillUses.contains { $0.action == .weaponHit(.handToHand) })
        #expect(world.skillUses.contains { $0.actor == opponent })
        #expect(world.skillUses.contains { $0.action == .blockedBlow && $0.actor == .player })
        #expect(world.skillUses.contains { $0.action == .armorHit && $0.actor == .player })
    }

    // MARK: - Casting

    /// A cast reports one use per effect naming a magic skill, at the spell's
    /// authored base cost times the effect's `Skill Usage Mult`.
    @Test func aCastReportsTheEffectsMagicSkill() throws {
        let store = WorldStateStore()
        let (spellbook, _) = try SpellbookFixture.runtime(store: store)
        let world = FakeCasterWorld()
        let runtime = CasterRuntime(
            spellbook: spellbook, values: SpellbookFixture.values(store: store)
        )
        runtime.attach(world: world)
        let key = SpellbookFixture.key(SpellbookFixture.Spell.firebolt)
        spellbook.learn(key, on: .player)
        try spellbook.equip(key, in: .right, on: .player)
        let spell = try #require(spellbook.record(key))

        runtime.begin(.right, on: .player)
        runtime.advance(delta: 2, on: .player)
        runtime.release(.right, on: .player)

        let use = try #require(world.skillUses.first)
        #expect(use.actor == .player)
        #expect(use.action == .spellEffect(skill: 20))
        #expect(use.amount == Float(spell.cost.cost))
    }
}
