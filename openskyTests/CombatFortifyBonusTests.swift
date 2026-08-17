// The fortify terms the damage formulas read (issue #472, roadmap item 19.9,
// scope point 3): which actor values each surface sums, and that a fortify effect
// measurably moves what `MeleeDamage.resolve` and `ArcheryDamage.resolve` return.
//
// Arithmetic over a value reader, with no store and no records, which is what
// makes the whole scope point a plain assertion. The actor values named here are
// the ones the vanilla records move — measured, and listed in
// `CombatFortifyBonus`.

import Foundation
@testable import opensky
import Testing

struct CombatFortifyBonusTests {
    /// Both families are read, not just one: an enchantment moves the `Modifier`
    /// value and a potion the `Power Modifier` one, and the two add.
    @Test func bothTheEnchantmentAndPotionValuesAreRead() throws {
        let enchantment = try #require(ActorValueIdentity.index(named: "One-Handed Modifier"))
        let potion = try #require(ActorValueIdentity.index(named: "One-Handed Power Modifier"))
        #expect(CombatFortifyBonus.oneHandedIndices == [enchantment, potion])

        let multiplier = CombatFortifyBonus.melee(handType: .sword) { index in
            switch index {
            case enchantment: 20
            case potion: 30
            default: 0
            }
        }
        #expect(multiplier == 1.5)
    }

    /// The hand type selects which pair a swing reads, because that is the only
    /// thing this engine knows about a swing that separates one-handed from
    /// two-handed.
    @Test func theHandTypeSelectsWhichPairIsRead() throws {
        let oneHanded = try #require(ActorValueIdentity.index(named: "One-Handed Modifier"))
        let twoHanded = try #require(ActorValueIdentity.index(named: "Two-Handed Modifier"))
        let read: (Int32) -> Float? = { index in
            switch index {
            case oneHanded: 40
            case twoHanded: 10
            default: 0
            }
        }
        #expect(CombatFortifyBonus.melee(handType: .dagger, reading: read) == 1.4)
        #expect(CombatFortifyBonus.melee(handType: .mace, reading: read) == 1.4)
        #expect(CombatFortifyBonus.melee(handType: .greatsword, reading: read) == 1.1)
        #expect(CombatFortifyBonus.melee(handType: .battleaxe, reading: read) == 1.1)
        // An unarmed hit is neither: `Unarmed Damage` is the value vanilla moves
        // for it, and this term is deliberately not it.
        #expect(CombatFortifyBonus.melee(handType: .handToHand, reading: read) == 1)
        #expect(CombatFortifyBonus.melee(handType: .shield, reading: read) == 1)
    }

    /// A bow reads the archery pair whether it is asked for as a swing or as a
    /// shot, so the two entry points cannot disagree.
    @Test func aBowReadsTheArcheryPairFromEitherEntryPoint() throws {
        let archery = try #require(ActorValueIdentity.index(named: "Marksman Modifier"))
        let read: (Int32) -> Float? = { $0 == archery ? 25 : 0 }
        #expect(CombatFortifyBonus.archery(reading: read) == 1.25)
        #expect(CombatFortifyBonus.melee(handType: .bow, reading: read) == 1.25)
        #expect(CombatFortifyBonus.melee(handType: .crossbow, reading: read) == 1.25)
    }

    @Test func blockReadsItsOwnPair() throws {
        let block = try #require(ActorValueIdentity.index(named: "Block Modifier"))
        #expect(CombatFortifyBonus.block { $0 == block ? 50 : 0 } == 1.5)
    }

    /// An unreadable value contributes nothing rather than poisoning the sum, and
    /// a detrimental total below -100 points floors at zero instead of turning a
    /// hit into a heal.
    @Test func unreadableAndAbsurdValuesDegradeSafely() {
        #expect(CombatFortifyBonus.multiplier(of: [1, 2]) { _ in nil } == 1)
        #expect(CombatFortifyBonus.multiplier(of: [1]) { _ in .nan } == 1)
        #expect(CombatFortifyBonus.multiplier(of: [1]) { _ in -250 } == 0)
        #expect(CombatFortifyBonus.multiplier(of: []) { _ in 100 } == 1)
    }

    // MARK: - Through the damage formulas

    /// The scope point end to end: a Fortify One-Handed effect changes what a
    /// landed swing takes off, and nothing else about the result moves.
    @Test func aFortifyEffectChangesTheMeleeDamage() throws {
        let index = try #require(ActorValueIdentity.index(named: "One-Handed Modifier"))
        let weapon = MeleeWeaponProfile(damage: 10, reach: 1, handType: .sword)
        let plain = MeleeDamage.resolve(weapon: weapon, block: nil, settings: .synthetic)
        #expect(plain.applied == 10)
        #expect(plain.attackMultiplier == 1)
        #expect(!plain.wasFortified)

        let fortified = MeleeDamage.resolve(
            weapon: weapon,
            block: nil,
            settings: .synthetic,
            attackMultiplier: CombatFortifyBonus.melee(handType: weapon.handType) {
                $0 == index ? 40 : 0
            }
        )
        #expect(fortified.applied == 14)
        #expect(fortified.base == 10)
        #expect(fortified.attackMultiplier == 1.4)
        #expect(fortified.wasFortified)
    }

    /// The attacker's fortify raises the damage dealt through a block without
    /// raising the block: the quoted block formula scales on the WEAP number
    /// rather than the enchanted one.
    @Test func theAttackTermDoesNotGrowTheBlock() {
        let weapon = MeleeWeaponProfile(damage: 20, reach: 1, handType: .sword)
        let plain = MeleeDamage.resolve(
            weapon: weapon, block: .weapon, settings: .synthetic
        )
        let fortified = MeleeDamage.resolve(
            weapon: weapon, block: .weapon, settings: .synthetic, attackMultiplier: 2
        )
        #expect(fortified.blockedFraction == plain.blockedFraction)
        #expect(fortified.applied == plain.applied * 2)
    }

    /// The blocker's own term is the other parameter, and it moves the fraction
    /// rather than the damage dealt.
    @Test func theBlockTermMovesTheBlockedFraction() {
        let weapon = MeleeWeaponProfile(damage: 20, reach: 1, handType: .sword)
        let plain = MeleeDamage.resolve(weapon: weapon, block: .weapon, settings: .synthetic)
        let fortified = MeleeDamage.resolve(
            weapon: weapon, block: .weapon, settings: .synthetic, bonusMultiplier: 1.5
        )
        #expect(fortified.blockedFraction > plain.blockedFraction)
        #expect(fortified.applied < plain.applied)
    }

    /// The archery side already carried the term; this pins that a Fortify Archery
    /// effect reaches it.
    @Test func aFortifyEffectChangesTheArrowDamage() throws {
        let index = try #require(ActorValueIdentity.index(named: "Marksman Modifier"))
        let plain = ArcheryDamage.resolve(bowDamage: 20, arrowDamage: 10, skill: 0)
        let fortified = ArcheryDamage.resolve(
            bowDamage: 20,
            arrowDamage: 10,
            skill: 0,
            bonusMultiplier: CombatFortifyBonus.archery { $0 == index ? 50 : 0 }
        )
        #expect(plain.applied == 30)
        #expect(fortified.applied == 45)
    }
}
