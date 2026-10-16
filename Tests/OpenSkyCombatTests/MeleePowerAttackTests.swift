// Power attacks and bashes: a held press becomes a power attack and pays
// stamina, the guard turns a press into a bash, and both change the hit.
// Numbers from UESP "Skyrim:Combat" and "Skyrim:Block".

@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
@testable import OpenSkyPhysics
import simd
import Testing

@MainActor
struct MeleePowerAttackTests {
    @Test func aTapSwingsAndAHoldPowersUp() {
        var hold = MeleeHold()
        hold.pressed(asBash: false)
        #expect(hold.advance(held: false, deltaTime: 0.1) == .tapped(.normal))
        hold.pressed(asBash: false)
        #expect(hold.advance(held: true, deltaTime: 0.2) == nil)
        #expect(hold.advance(held: true, deltaTime: 0.2) == .held(.power))
        hold.startedPowerAttack(coolDown: 1)
        hold.pressed(asBash: false)
        #expect(hold.advance(held: true, deltaTime: 0.4) == .tapped(.normal))
        hold.pressed(asBash: true)
        #expect(hold.advance(held: true, deltaTime: 0.4) == .held(.powerBash))
    }

    @Test func theDirectionPicksThePowerAttackEvent() {
        #expect(MeleePowerDirection(moveForward: 1, moveRight: 0).eventName
            == CombatGraphNames.attackPowerStartForward)
        #expect(MeleePowerDirection(moveForward: 0, moveRight: -1).eventName
            == CombatGraphNames.attackPowerStartLeft)
        #expect(MeleePowerDirection(moveForward: 0, moveRight: 0).eventName
            == CombatGraphNames.attackPowerStartInPlace)
    }

    /// A 10-weight weapon: (20 + 10) * 2 = 60 stamina, and twice the damage.
    @Test func aHeldPressPaysStaminaAndDoublesTheHit() {
        let world = FakeMeleeWorld()
        world.targets = [MeleeTarget(key: .generated(1), feet: SIMD3(80, 0, 0))]
        world.stamina = 100
        let runtime = MeleeCombatRuntimeTests.runtime(world: world, damage: 10)
        runtime.weapon = MeleeWeaponProfile(damage: 10, reach: 1, weight: 10)
        runtime.handleGraphEvents(MeleeCombatRuntimeTests.drawEvents)

        runtime.acceptFrame(MeleeIntent(attack: true, attackHeld: true, deltaTime: 0.1))
        runtime.acceptFrame(MeleeIntent(attackHeld: true, deltaTime: 0.25))
        runtime.handleGraphEvents([
            CombatGraphNames.attackPowerStartInPlace, CombatGraphNames.hitFrame
        ])

        #expect(world.raised.contains(CombatGraphNames.attackPowerStartInPlace))
        #expect(!world.raised.contains(CombatGraphNames.attackStart))
        #expect(world.staminaPaid == [60])
        #expect(world.damage == [.generated(1): 20])
        #expect(runtime.trace.last?.kind == .power)
    }

    @Test func withNoStaminaAHeldPressSwingsPlainly() {
        let world = FakeMeleeWorld()
        world.stamina = 0.5
        let runtime = MeleeCombatRuntimeTests.runtime(world: world, damage: 10)
        runtime.handleGraphEvents(MeleeCombatRuntimeTests.drawEvents)

        runtime.acceptFrame(MeleeIntent(attack: true, attackHeld: true, deltaTime: 0.4))

        #expect(world.raised.contains(CombatGraphNames.attackStart))
        #expect(runtime.strikeKind == .normal)
    }

    /// A shield of rating 20 at Block 50 for the player: 20 * 0.5 * (0.1 + 0.5 * 0.15).
    @Test func aPressWithTheGuardUpBashes() {
        let world = FakeMeleeWorld()
        world.targets = [MeleeTarget(key: .generated(1), feet: SIMD3(80, 0, 0))]
        world.shieldRating = 20
        let runtime = MeleeCombatRuntimeTests.runtime(world: world, damage: 10)
        runtime.handleGraphEvents(MeleeCombatRuntimeTests.drawEvents)

        runtime.acceptFrame(MeleeIntent(attack: true, block: true))
        runtime.handleGraphEvents([CombatGraphNames.bashStart, CombatGraphNames.hitFrame])

        #expect(world.raised.contains(CombatGraphNames.bashStart))
        #expect(world.staminaPaid == [35])
        let applied = world.damage[.generated(1)] ?? 0
        #expect(abs(applied - 1.75) < 1e-4)
    }

    @Test func bashDamageFollowsTheBlockSkill() {
        let settings = PowerAttackSettings.vanilla
        let weapon = MeleeBash.damage(
            BashSource(weaponDamage: 10, shieldRating: nil, blockSkill: 50),
            isPlayer: true, isPower: false, settings: settings
        )
        #expect(abs(weapon - 1.5) < 1e-5)
        let shield = MeleeBash.damage(
            BashSource(weaponDamage: 10, shieldRating: 20, blockSkill: 0),
            isPlayer: false, isPower: true, settings: settings
        )
        #expect(abs(shield - 1.5) < 1e-5)
    }

    @Test func settingsComeFromTheLoadOrder() throws {
        let store = try GameSettingFixture.store([
            "fPowerAttackDefaultBonus": .float(0.5),
            "fStaminaBashBase": .float(20),
            "fWeaponBashMax": .float(0.4)
        ])
        let settings = PowerAttackSettings.resolve(store: store)
        #expect(settings.damageBonus == 0.5)
        #expect(settings.bashStamina == 20)
        #expect(settings.weaponBash.max == 0.4)
        #expect(settings.weaponBash.playerMax == 0.5)
        #expect(settings.powerAttackStamina(weight: 10) == 60)
    }
}
