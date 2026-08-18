// A fighting caster end to end (issue #473, roadmap item 19.10, scope point 6):
// the decision, the readied hand, the spent magicka, the delivered spell and the
// health it takes off, over stepped time.
//
// The behavior half — when a cast is chosen and what is chosen — is
// `CombatCastingBehaviorTests`. This suite is about everything downstream of the
// decision going through the shipping path: `SpellbookRuntime`, `CasterRuntime`,
// the 19.8 delivery and `ActiveEffectRuntime`, with no second cast loop for
// actors anywhere in it.

import Foundation
@testable import opensky
import Testing

@MainActor
struct CombatLoopCastingTests {
    private typealias Chain = CombatCastingChain

    /// A hostile target-actor spell: no charge, 1500-unit range, one hostile
    /// fire entry. The whole pipeline in the fewest seconds.
    private static let spark = SpellbookFixture.Spell.sparkAtTarget
    /// A hostile aimed spell, which leaves as a projectile instead.
    private static let firebolt = SpellbookFixture.Spell.firebolt

    // MARK: - The acceptance picture

    @Test func aCasterNPCDamagesThePlayerThroughTheWholePipeline() throws {
        let chain = try Chain()
        chain.teach(Self.spark)
        chain.casterFeet = SIMD3(900, 0, 0)
        let magickaBefore = chain.casterMagicka

        chain.advance(seconds: 3)

        #expect(chain.combat.phase(of: Chain.caster)?.isEngaged == true)
        #expect(chain.combat.behaviors[Chain.caster]?.castCount ?? 0 > 0)
        #expect(!chain.spellHits.isEmpty)
        #expect(chain.playerHealth < 100)
        #expect(chain.casterMagicka < magickaBefore)
    }

    @Test func theSpellThatLandedIsTheOneTheCasterKnows() throws {
        let chain = try Chain()
        chain.teach(Self.spark)
        chain.casterFeet = SIMD3(900, 0, 0)

        chain.advance(seconds: 3)

        let hit = try #require(chain.spellHits.first)
        #expect(hit.payload.spell == SpellbookFixture.key(Self.spark))
        #expect(hit.payload.caster == Chain.caster)
        #expect(hit.payload.isHostile)
    }

    @Test func anAimedSpellLeavesTheCasterAsAProjectile() throws {
        let chain = try Chain()
        chain.teach(Self.firebolt)
        chain.casterFeet = SIMD3(900, 0, 0)

        chain.advance(seconds: 3)

        let payload = try #require(chain.firedProjectiles.first)
        #expect(payload.caster == Chain.caster)
        // The MGEF's own PROJ travels with the payload, and what it carries is
        // what lands (the flight itself is `ProjectileSpellTests`).
        #expect(payload.projectile != nil)
        #expect(chain.playerHealth < 100)
    }

    // MARK: - Falling back

    @Test func aCasterWithNoMagickaFightsWithItsHandsInstead() throws {
        let chain = try Chain()
        chain.teach(Self.spark)
        chain.values.set(.magicka, to: 0, on: chain.casterHolder)
        chain.casterFeet = SIMD3(60, 0, 0)

        chain.advance(seconds: 3)

        let machine = try #require(chain.combat.behaviors[Chain.caster])
        #expect(machine.castCount == 0)
        #expect(machine.attackCount > 0)
        #expect(chain.playerHealth < 100)
    }

    @Test func aCasterThatKnowsNothingCastableIsUnchangedByThisItem() throws {
        let chain = try Chain()
        chain.teach(SpellbookFixture.Spell.fastHealing)
        chain.casterFeet = SIMD3(60, 0, 0)

        chain.advance(seconds: 3)

        let machine = try #require(chain.combat.behaviors[Chain.caster])
        #expect(machine.castCount == 0)
        #expect(machine.attackCount > 0)
        #expect(chain.spellHits.isEmpty)
    }

    // MARK: - Interruptions reach the cast loop

    @Test func aStaggerMidChargeLeavesNoCastRunning() throws {
        let chain = try Chain()
        chain.teach(Self.firebolt)
        chain.casterFeet = SIMD3(900, 0, 0)
        chain.advance(seconds: 0.2)
        #expect(chain.caster.phase(of: .right, on: Chain.caster).isCasting)

        chain.combat.noteStagger(of: Chain.caster)

        #expect(!chain.caster.phase(of: .right, on: Chain.caster).isCasting)
        #expect(chain.firedProjectiles.isEmpty)
    }

    @Test func stoppingTheFightMidChargeLeavesNoCastRunning() throws {
        let chain = try Chain()
        chain.teach(Self.firebolt)
        chain.casterFeet = SIMD3(900, 0, 0)
        chain.advance(seconds: 0.2)

        chain.combat.stopCombat(Chain.caster)

        #expect(!chain.caster.phase(of: .right, on: Chain.caster).isCasting)
    }

    @Test func aCasterThatDiesMidChargeStopsCasting() throws {
        let chain = try Chain()
        chain.teach(Self.firebolt)
        chain.casterFeet = SIMD3(900, 0, 0)
        chain.advance(seconds: 0.2)

        chain.casterIsDead = true
        chain.advance(seconds: 0.2)

        #expect(!chain.caster.phase(of: .right, on: Chain.caster).isCasting)
        #expect(chain.firedProjectiles.isEmpty)
    }

    // MARK: - Determinism

    @Test func twoRunsOfTheSameFightSpendTheSameMagicka() throws {
        let first = try Chain()
        let second = try Chain()
        for chain in [first, second] {
            chain.teach(Self.spark)
            chain.casterFeet = SIMD3(900, 0, 0)
            chain.advance(seconds: 4)
        }
        #expect(first.casterMagicka == second.casterMagicka)
        #expect(first.playerHealth == second.playerHealth)
        #expect(first.spellHits.count == second.spellHits.count)
    }
}
