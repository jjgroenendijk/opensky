// Damage and the block formula (issue #195, roadmap item 15.4, scope point 6).
//
// The issue's acceptance says "damage matches WEAP data; blocking reduces it
// per the pinned formula", so the formula is written out longhand in the
// expectations rather than being recomputed from the same helper it is testing.
// The constants are the ones the install carries — 0.300 base, 0.200 scaling,
// 2.000 skill weight, 0.700 cap — which are not the ones UESP prints; see
// `CombatSettings` for the reading that reconciles the two.

@testable import opensky
import Testing

struct MeleeDamageTests {
    private let settings = CombatSettings.synthetic

    @Test func unblockedDamageIsTheWeaponsBaseDamage() {
        let weapon = MeleeWeaponProfile(damage: 24, reach: 1)

        let result = MeleeDamage.resolve(weapon: weapon, block: nil, settings: settings)

        #expect(result.base == 24)
        #expect(result.applied == 24)
        #expect(result.blockedFraction == 0)
        #expect(result.wasBlocked == false)
    }

    @Test func aWeaponBlockFollowsThePinnedFormula() {
        let weapon = MeleeWeaponProfile(damage: 10, reach: 1)

        let result = MeleeDamage.resolve(
            weapon: weapon, block: .weapon, settings: settings, blockSkill: 15
        )

        // 0.3 + 0.2 * 10 * (1 + 15 * 2 / 100) / 100 = 0.3 + 0.026 = 0.326
        #expect(abs(result.blockedFraction - 0.326) < 0.0001)
        #expect(abs(result.applied - 10 * (1 - 0.326)) < 0.001)
    }

    @Test func aShieldBlockScalesOnTheShieldsOwnArmorRating() {
        let weapon = MeleeWeaponProfile(damage: 10, reach: 1)

        let result = MeleeDamage.resolve(
            weapon: weapon,
            block: .shield(baseArmorRating: 15),
            settings: settings,
            blockSkill: 100
        )

        // 0.45 + 0.2 * 15 * (1 + 100 * 2 / 100) / 100 = 0.45 + 0.09 = 0.54
        #expect(abs(result.blockedFraction - 0.54) < 0.0001)
    }

    @Test func theWeaponBranchScalesOnTheAttackersDamageNotTheBlockers() {
        let light = MeleeWeaponProfile(damage: 4, reach: 1)
        let heavy = MeleeWeaponProfile(damage: 40, reach: 1)

        let againstLight = MeleeDamage.resolve(
            weapon: light, block: .weapon, settings: settings
        )
        let againstHeavy = MeleeDamage.resolve(
            weapon: heavy, block: .weapon, settings: settings
        )

        // A heavier incoming weapon is blocked more effectively, which is the
        // reading UESP is explicit about and which looks like a bug until read.
        #expect(againstHeavy.blockedFraction > againstLight.blockedFraction)
    }

    @Test func anUnarmedAttackerGivesTheFlatWeaponBase() {
        let result = MeleeDamage.resolve(
            weapon: MeleeWeaponProfile(damage: 0, reach: 1),
            block: .weapon,
            settings: settings
        )
        #expect(abs(result.blockedFraction - 0.3) < 0.0001)
    }

    @Test func blockingIsCappedAtBlockMax() {
        let result = MeleeDamage.resolve(
            weapon: MeleeWeaponProfile(damage: 1000, reach: 1),
            block: .weapon,
            settings: settings,
            blockSkill: 100
        )

        #expect(result.blockedFraction == settings.blockMax.value)
        #expect(abs(result.applied - 1000 * (1 - 0.7)) < 0.01)
    }

    @Test func aPowerAttackIsBlockedLessWell() {
        let weapon = MeleeWeaponProfile(damage: 10, reach: 1)

        let normal = MeleeDamage.resolve(
            weapon: weapon, block: .weapon, settings: settings
        )
        let power = MeleeDamage.resolve(
            weapon: weapon, block: .weapon, settings: settings, isPowerAttack: true
        )

        #expect(
            abs(power.blockedFraction
                - normal.blockedFraction * settings.blockPowerAttackMult.value) < 0.0001
        )
    }

    @Test func theBonusMultiplierCarriesThePerkAndEnchantmentTerms() {
        let weapon = MeleeWeaponProfile(damage: 10, reach: 1)

        let plain = MeleeDamage.resolve(weapon: weapon, block: .weapon, settings: settings)
        let perked = MeleeDamage.resolve(
            weapon: weapon, block: .weapon, settings: settings, bonusMultiplier: 1.5
        )

        #expect(abs(perked.blockedFraction - plain.blockedFraction * 1.5) < 0.0001)
    }

    @Test func nonFiniteInputsClampRatherThanPropagate() {
        let broken = MeleeWeaponProfile(damage: .nan, reach: 1)

        let result = MeleeDamage.resolve(weapon: broken, block: .weapon, settings: settings)

        #expect(result.base == 0)
        #expect(result.applied.isFinite)
        // A non-finite armour rating contributes nothing rather than
        // saturating the cap, so a broken record leaves the flat shield base.
        #expect(
            abs(MeleeDamage.blockedFraction(
                attackerDamage: 10,
                block: .shield(baseArmorRating: .infinity),
                settings: settings
            ) - settings.shieldBaseFactor.value) < 0.0001
        )
    }
}
