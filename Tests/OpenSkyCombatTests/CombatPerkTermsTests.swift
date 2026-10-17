// The perk entry points of a weapon hit, over a fake world whose perks scale or
// add to each entry point's value.

@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import simd
import Testing

@MainActor
struct CombatPerkTermsTests {
    private static let guardKey = ReferenceKey.generated(1)

    private static func coordinator(
        _ world: FakeCoordinatorWorld, items: ItemDefinitionStore? = nil
    ) -> CombatCoordinator {
        let coordinator = CombatCoordinator()
        coordinator.attach(world: world)
        coordinator.wireMelee(settings: .synthetic, items: items, impacts: nil)
        return coordinator
    }

    private static func detected() -> FakeCoordinatorWorld {
        let world = FakeCoordinatorWorld()
        world.detects[guardKey] = [.player]
        return world
    }

    private static let sword = CombatBlow(attacker: .player, handType: .sword, baseDamage: 10)

    /// Both sides' damage perks scale the blow; `Calculate Weapon Damage` adds to the base.
    @Test func bothSidesDamagePerksScaleTheBlow() {
        let world = Self.detected()
        world.perkFactors[.modAttackDamage] = 1.5
        world.perkFactors[.modIncomingDamage] = 0.5
        world.perkAddends[.calculateWeaponDamage] = 20
        let strike = Self.coordinator(world).strike(Self.sword, on: Self.guardKey)

        #expect(strike.perkMultiplier == 0.75)
        #expect(strike.weaponDamageBonus == 20)
        #expect(strike.damage(base: 10) == 22.5)
        #expect(world.perkQuestions[.modAttackDamage]?[.target] == Self.guardKey)
        #expect(world.perkQuestions[.modIncomingDamage]?[.perkOwner] == Self.guardKey)
        #expect(world.perkQuestions[.modIncomingDamage]?[.attacker] == .player)
    }

    /// The chance starts at 0, so only a perk makes a critical; its damage is added last.
    @Test func aCriticalNeedsAPerkAndAddsItsDamage() {
        let world = Self.detected()
        let coordinator = Self.coordinator(world)
        #expect(!coordinator.strike(Self.sword, on: Self.guardKey).isCritical)

        world.perkAddends[.calculateCriticalChance] = 100
        world.perkAddends[.calculateCriticalDamage] = 7
        let strike = coordinator.strike(Self.sword, on: Self.guardKey)

        #expect(strike.isCritical)
        #expect(strike.damage(base: 10) == 17)
    }

    /// A bash takes `Mod Bashing Damage` and none of the swing's attack terms.
    @Test func aBashTakesTheBashPerkAlone() {
        let world = Self.detected()
        world.perkFactors[.modBashingDamage] = 2
        world.perkFactors[.modAttackDamage] = 3
        world.perkAddends[.calculateCriticalChance] = 100
        var bash = Self.sword
        bash.kind = .bash
        let strike = Self.coordinator(world).strike(bash, on: Self.guardKey)

        #expect(strike.bashMultiplier == 2)
        #expect(strike.perkMultiplier == 1)
        #expect(!strike.isCritical)
    }

    @Test func aPowerAttackAndTheStaggerTakeTheirPerks() {
        let world = Self.detected()
        world.perkFactors[.modPowerAttackDamage] = 1.25
        world.perkFactors[.modTargetStagger] = 2
        world.perkFactors[.modIncomingStagger] = 0.25
        var power = Self.sword
        power.kind = .power
        let strike = Self.coordinator(world).strike(power, on: Self.guardKey)

        #expect(strike.powerMultiplier == 1.25)
        #expect(strike.staggerMultiplier == 0.5)
    }

    /// The attacker's `Mod Target Damage Resistance` scales the target's rating.
    @Test func theAttackerCutsTheTargetsArmour() throws {
        let world = Self.detected()
        let damageResist = try #require(ActorValueIdentity.index(named: "Damage Resist"))
        world.values[Self.guardKey] = [damageResist: 100]
        let items = try ItemDefinitionStore(file: SpellStoreFixture.plugin(records: []))
        let coordinator = Self.coordinator(world, items: items)
        let full = coordinator.armorFraction(of: Self.guardKey, against: Self.sword)
        world.perkFactors[.modTargetDamageResistance] = 0.5
        let halved = coordinator.armorFraction(of: Self.guardKey, against: Self.sword)

        #expect(full > 0)
        #expect(abs(halved - full / 2) < 0.0001)
    }

    @Test func sweepIsAPerkAndASwingSpellLandsOnTheOwner() throws {
        let world = Self.detected()
        let coordinator = Self.coordinator(world)
        #expect(!coordinator.perkSweeps(Self.sword))
        world.perkAddends[.setSweepAttack] = 1
        #expect(coordinator.perkSweeps(Self.sword))

        let spell = try Self.spell()
        world.perkSpells[.applyWeaponSwingSpell] = spell
        coordinator.applyPerkSwingSpell(
            CombatBlow(attacker: Self.guardKey, handType: .sword), at: .player
        )
        #expect(world.spellHits.map(\.targets.first?.key) == [.player])
        #expect(world.perkQuestions[.applyWeaponSwingSpell]?[.attacker] == Self.guardKey)
    }

    /// An unarmed blow is not a combat hit; an armed one lands the perk's spell.
    @Test func aCombatHitSpellNeedsAWeapon() throws {
        let world = Self.detected()
        world.perkSpells[.applyCombatHitSpell] = try Self.spell()
        let coordinator = Self.coordinator(world)

        coordinator.applyPerkHitSpell(Self.sword, on: Self.guardKey)
        #expect(world.spellHits.isEmpty)
        var armed = Self.sword
        armed.weapon = FormID(0x0123)
        coordinator.applyPerkHitSpell(armed, on: Self.guardKey)
        #expect(world.spellHits.map(\.targets.first?.key) == [Self.guardKey])
        #expect(world.spellHits.first?.payload.caster == .player)
    }

    /// Only the frame that enters sneak casts; staying crouched does not cast again.
    @Test func enteringSneakCastsTheSneakingSpellOnce() throws {
        let world = Self.detected()
        world.perkSpells[.applySneakingSpell] = try Self.spell()
        let coordinator = Self.coordinator(world)

        coordinator.notePlayerSneaking(false)
        coordinator.notePlayerSneaking(true)
        coordinator.notePlayerSneaking(true)
        #expect(world.spellHits.map(\.targets.first?.key) == [.player])
        coordinator.notePlayerSneaking(false)
        coordinator.notePlayerSneaking(true)
        #expect(world.spellHits.count == 2)
    }

    @Test func graphFlagsFollowThePassingPerksFrameByFrame() {
        let world = Self.detected()
        let coordinator = Self.coordinator(world)
        world.perkTexts[.setBooleanGraphVariable] = ["bPerkQuickShot", "bPerkQuickdraw"]
        #expect(coordinator.perkGraphFlagChanges() == [
            "bPerkQuickShot": true,
            "bPerkQuickdraw": true
        ])
        #expect(coordinator.perkGraphFlagChanges().isEmpty)
        world.perkTexts[.setBooleanGraphVariable] = ["bPerkQuickdraw"]
        #expect(coordinator.perkGraphFlagChanges() == ["bPerkQuickShot": false])
    }

    private static func spell() throws -> ResolvedSpell {
        let file = try SpellStoreFixture.plugin(records: SpellStoreFixture.effectRecords + [
            ESMFixture.record("SPEL", formID: 0x42, data: SpellStoreFixture.spellFields(
                editorID: "PerkTestSpell",
                name: "Perk Test Spell",
                spit: SpellFixture.spit(),
                effects: [SpellStoreFixture.EffectSpec(0x50, magnitude: 10)]
            ))
        ])
        return try #require(SpellStore(plugins: [("Base.esm", file)])
            .spell(editorID: "PerkTestSpell"))
    }
}
