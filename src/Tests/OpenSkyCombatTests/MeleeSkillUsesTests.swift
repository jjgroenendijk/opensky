// What one melee blow teaches: the action each use reports, and the Block amounts
// UESP "Skyrim:Block" lists for blocks and bashes.

@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyProgressionInterface
import Testing

struct MeleeSkillUsesTests {
    private static let sword = ResolvedFormID(plugin: "Test.esm", objectID: 0x800)

    private static func blow(
        kind: MeleeStrikeKind = .normal,
        damage: MeleeDamageResult = MeleeDamageResult(base: 10, blockedFraction: 0, applied: 10),
        landed: Bool = true,
        shield: Bool = false
    ) -> MeleeSkillUseBlow {
        MeleeSkillUseBlow(
            attacker: .player,
            target: .generated(1),
            handType: .sword,
            kind: kind,
            damage: damage,
            landed: landed,
            bashedWithShield: shield,
            weapon: sword
        )
    }

    @Test func aSwingReportsNormalUseWithItsWeapon() throws {
        let uses = MeleeSkillUses.events(for: Self.blow(), settings: .vanilla)
        let hit = try #require(uses.first)
        #expect(hit.action == .weaponHit(.sword))
        #expect(hit.amount == 10)
        #expect(hit.advanceAction == .normalUsage)
        #expect(hit.object == Self.sword)
        #expect(uses.last?.action == .armorHit)
    }

    @Test func aPowerAttackReportsThePowerAttackAction() {
        let uses = MeleeSkillUses.events(for: Self.blow(kind: .power), settings: .vanilla)
        #expect(uses.first?.action == .weaponHit(.sword))
        #expect(uses.first?.advanceAction == .powerAttack)
    }

    /// UESP "Skyrim:Leveling": "5 base XP for a shield bash"; a weapon bash gives a fifth.
    @Test func aBashTeachesBlockByWhatItWasMadeWith() {
        for (kind, shield, amount) in [
            (MeleeStrikeKind.bash, true, Float(5)), (.bash, false, 1), (.powerBash, true, 5)
        ] {
            let uses = MeleeSkillUses.events(
                for: Self.blow(kind: kind, shield: shield), settings: .vanilla
            )
            #expect(uses.first?.action == .bash)
            #expect(uses.first?.action.skillIndex == ActorValueIdentity.index(named: "Block"))
            #expect(uses.first?.amount == amount)
            #expect(uses.first?.advanceAction == .bash)
            #expect(!uses.contains { $0.action == .weaponHit(.sword) })
        }
    }

    @Test func aMissedBashTeachesNothingToTheAttacker() {
        let uses = MeleeSkillUses.events(
            for: Self.blow(kind: .bash, landed: false),
            settings: .vanilla
        )
        #expect(uses.map(\.action) == [.armorHit])
    }

    /// "Blocking with a shield grants 2 times the XP compared to blocking with a weapon."
    @Test func aShieldBlockTeachesTwiceAWeaponBlock() throws {
        func blocked(_ block: MeleeBlockKind) throws -> Float {
            let damage = MeleeDamageResult(
                base: 10, blockedFraction: 0.5, applied: 5, block: block
            )
            let uses = MeleeSkillUses.events(for: Self.blow(damage: damage), settings: .vanilla)
            let use = try #require(uses.first { $0.action == .blockedBlow })
            #expect(use.actor == .generated(1))
            #expect(use.advanceAction == .normalUsage)
            return use.amount
        }
        #expect(try blocked(.weapon) == 5)
        #expect(try blocked(.shield(baseArmorRating: 20)) == 10)
    }

    @Test func aLoadOrderSettingWins() throws {
        let store = try GameSettingFixture.store([
            "fShieldBashSkillUseBase": .float(7),
            "fBlockSkillUseMult": .float(3),
            "fWeaponBashSkillUseMult": .float(0)
        ])
        let settings = MeleeSkillUseSettings.resolve(store: store)
        #expect(settings.bash(damage: 4, withShield: true) == 7)
        #expect(settings.blocked(absorbed: 2, withShield: true) == 6)
        #expect(settings.bash(damage: 4, withShield: false) == 1)
        #expect(settings.blocked(absorbed: 2, withShield: false) == 2)
    }
}
