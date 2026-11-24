// The damage and armour the item card shows: the player's skill, perks, and the
// item's tempering, over a fake world.

import Foundation
@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface
import Testing

@MainActor
struct CombatShownStatsTests {
    private static let sword = FormID(0x800)
    private static let cuirass = FormID(0x900)

    private static func coordinator(_ world: FakeCoordinatorWorld) throws -> CombatCoordinator {
        var weapon = ESMFixture.field("EDID", ESMFixture.zstring("Sword"))
        weapon += ESMFixture.field(
            "DATA", InventoryFixture.weaponData(value: 25, weight: 9, damage: 10)
        )
        weapon += ESMFixture.field(
            "DNAM", InventoryFixture.weaponDNAM(animation: 1, speed: 1, reach: 1, flags: 0)
        )
        var armour = ESMFixture.field("EDID", ESMFixture.zstring("Cuirass"))
        var bod2 = Data()
        bod2.appendUInt32(1 << 2)
        bod2.appendUInt32(1)
        armour += ESMFixture.field("BOD2", bod2)
        armour += ESMFixture.field(
            "DATA", InventoryFixture.valueWeightData(value: 125, weight: 30)
        )
        var rating = Data()
        rating.appendUInt32(2000)
        armour += ESMFixture.field("DNAM", rating)
        let items = try ItemDefinitionStore(file: SpellStoreFixture.plugin(records: [
            ESMFixture.record("WEAP", formID: sword.rawValue, data: weapon),
            ESMFixture.record("ARMO", formID: cuirass.rawValue, data: armour)
        ]))
        return CombatCoordinator(
            world: world,
            data: CombatSessionData(combat: .synthetic, archery: .synthetic, items: items)
        )
    }

    /// Tempering adds to the base; the skill factor and `Mod Attack Damage` scale it.
    @Test func aWeaponShowsItsDamageAfterSkillPerksAndTempering() throws {
        let world = FakeCoordinatorWorld()
        let oneHanded = try #require(SkillUseAction.weaponHit(.sword).skillIndex)
        world.values[.player] = [oneHanded: 100]
        world.perkFactors[.modAttackDamage] = 1.5
        let combat = try Self.coordinator(world)
        let skill = WeaponStrikeRules.playerSkillMultiplier(
            skill: 100, settings: combat.shared.weaponDamage
        )

        let shown = combat.shownDamage(of: Self.sword, temperLevel: 1)

        #expect(shown == Int((11 * skill * 1.5).rounded()))
        #expect(combat.shownDamage(of: Self.cuirass, temperLevel: 0) == nil)
    }

    /// The skill factor is rounded up before `Mod Armor Rating` scales it; an armour
    /// spell is the bar's bonus.
    @Test func armourShowsItsRatingAfterSkillAndPerks() throws {
        let world = FakeCoordinatorWorld()
        let heavy = try #require(ActorValueIdentity.index(named: "Heavy Armor"))
        let resist = try #require(ActorValueIdentity.index(named: "Damage Resist"))
        world.values[.player] = [heavy: 50, resist: 40]
        world.perkFactors[.modArmorRating] = 1.25
        let combat = try Self.coordinator(world)
        let scaled = WeaponStrikeRules.armorRating(
            pieces: [WornArmorPiece(rating: 20, type: .heavy)],
            skills: ArmorSkills(light: 0, heavy: 50),
            isPlayer: true,
            settings: combat.shared.weaponDamage
        )

        #expect(combat.shownArmourRating(of: Self.cuirass, temperLevel: 0)
            == scaled.rounded(.up) * 1.25)
        #expect(combat.shownArmourRating(of: Self.sword, temperLevel: 0) == nil)
        #expect(combat.shownArmourBonus == 40)
    }
}
