// Skill, sneak-attack, and armour terms, worked by hand from the UESP pages
// "Skyrim:Weapons", "Skyrim:Sneak", and "Skyrim:Armor".

import OpenSkyActorsInterface
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import Testing

struct WeaponStrikeRulesTests {
    private let settings = WeaponDamageSettings.vanilla

    @Test func playerSkillAddsHalfTheDamageAtOneHundred() {
        #expect(WeaponStrikeRules.playerSkillMultiplier(skill: 0, settings: settings) == 1)
        #expect(WeaponStrikeRules.playerSkillMultiplier(skill: 50, settings: settings) == 1.25)
        #expect(WeaponStrikeRules.playerSkillMultiplier(skill: 100, settings: settings) == 1.5)
    }

    @Test func sneakAttacksMultiplyByWeaponFamily() {
        #expect(WeaponStrikeRules.sneakMultiplier(handType: .dagger, settings: settings) == 3)
        #expect(WeaponStrikeRules.sneakMultiplier(handType: .greatsword, settings: settings) == 2)
        #expect(WeaponStrikeRules.sneakMultiplier(handType: .handToHand, settings: settings) == 2)
        #expect(WeaponStrikeRules.sneakMultiplier(handType: .bow, settings: settings) == 2)
        var halved = settings
        halved.sneakAttackBonusPercent = 50
        #expect(WeaponStrikeRules.sneakMultiplier(handType: .sword, settings: halved) == 1.5)
    }

    /// Two heavy pieces of 20 and 10 at Heavy Armor 100 on the player: 30 * 1.4 = 42
    /// rating, so 42 * 0.12% + 2 * 3% stops 11.04% of a blow.
    @Test func wornArmourStopsAPercentPerPointAndPerPiece() {
        let pieces = [
            WornArmorPiece(rating: 20, type: .heavy),
            WornArmorPiece(rating: 10, type: .heavy),
            WornArmorPiece(rating: 0, type: .clothing)
        ]
        let rating = WeaponStrikeRules.armorRating(
            pieces: pieces, skills: ArmorSkills(light: 0, heavy: 100), isPlayer: true,
            settings: settings
        )
        #expect(abs(rating - 42) < 1e-4)
        let fraction = WeaponStrikeRules.armorFraction(
            rating: rating, pieces: pieces, settings: settings
        )
        #expect(abs(fraction - 0.1104) < 1e-5)
    }

    @Test func anNPCScalesFurtherAndTheCapHolds() {
        let pieces = [WornArmorPiece(rating: 100, type: .light)]
        let rating = WeaponStrikeRules.armorRating(
            pieces: pieces, skills: ArmorSkills(light: 100, heavy: 0), isPlayer: false,
            extra: 50, settings: settings
        )
        #expect(rating == 300)
        #expect(WeaponStrikeRules.armorFraction(
            rating: 1000, pieces: pieces, settings: settings
        ) == 0.8)
    }

    @Test func theStrikeScalesTheBlockedDamage() {
        let strike = WeaponStrike(skillMultiplier: 1.5, sneakMultiplier: 3, armorFraction: 0.5)
        let result = MeleeDamage.resolve(
            weapon: MeleeWeaponProfile(damage: 10, reach: 1),
            block: nil,
            settings: .synthetic,
            strike: strike
        )
        #expect(result.applied == 22.5)
        #expect(result.strike.isSneakAttack)
    }

    @Test func settingsComeFromTheLoadOrder() throws {
        let store = try GameSettingFixture.store([
            "fDamagePCSkillMax": .float(2),
            "fCombatSneak1HDaggerMult": .float(5),
            "fMaxArmorRating": .float(90),
            "fArmorRatingPCMax": .float(2)
        ])
        let resolved = WeaponDamageSettings.resolve(store: store)
        #expect(resolved.playerSkillMax == 2)
        #expect(resolved.sneakDagger == 5)
        #expect(resolved.maxArmorRating == 90)
        #expect(resolved.armorRatingPlayerMax == 2)
        #expect(resolved.sneakHand == 2)
    }
}
