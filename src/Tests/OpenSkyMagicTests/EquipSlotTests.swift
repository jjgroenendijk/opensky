// What an item in a casting slot gives: the equip abilities of its effects, and the
// enchantment look of a readied weapon. Records are synthetic and built in code.

import Foundation
import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyInventoryInterface
@testable import OpenSkyMagic
import OpenSkyMagicFixtures
import OpenSkyMagicInterface
import Testing

@MainActor
struct EquipSlotTests {
    private static let granter: UInt32 = 0x0400
    private static let ability: UInt32 = 0x0410
    private static let grantingSpell: UInt32 = 0x0420

    private static var records: [Data] {
        [
            SpellbookFixture.magicEffect(
                formID: granter, editorID: "GrantingEffect",
                data: SpellbookFixture.effectData(equipAbility: ability)
            ),
            SpellbookFixture.spell(
                formID: ability, editorID: "GrantedAbility",
                equipType: SpellbookFixture.Slot.eitherHand,
                spit: SpellbookFixture.spit(type: 4, chargeTime: 0, casting: 0, delivery: 0),
                effects: [.init(SpellbookFixture.fortifyResistFire, 10, 0)]
            ),
            SpellbookFixture.spell(
                formID: grantingSpell, editorID: "GrantingSpell",
                equipType: SpellbookFixture.Slot.eitherHand,
                spit: SpellbookFixture.spit(type: 0, chargeTime: 0, casting: 1, delivery: 0),
                effects: [.init(granter, 5, 0)]
            )
        ]
    }

    private func coordinator() throws -> MagicCoordinator {
        var data = MagicSessionData()
        let index = try SpellbookFixture.index(extraRecords: Self.records)
        data.effects = MagicEffectsData(
            values: FixedActorValues(),
            store: SpellbookFixture.effectStore(index: index),
            pluginName: SpellbookFixture.pluginName,
            conditionRegistry: ConditionFunctionRegistry()
        )
        data.casting = try MagicCastingData(
            spellbook: SpellbookFixture.runtime(extraRecords: Self.records).0,
            values: FixedActorValues(),
            spellPluginName: SpellbookFixture.pluginName,
            baselines: nil
        )
        return MagicCoordinator(world: FakeMagicWorld(), data: data)
    }

    private func equipAbilities(on coordinator: MagicCoordinator) -> [ReferenceKey] {
        coordinator.withEffects { runtime in
            runtime.state(of: .player).effects.filter { $0.source.kind == .equipAbility }
                .map(\.source.record)
        } ?? []
    }

    @Test func aReadiedSpellGrantsItsEquipAbilityUntilItLeavesTheHand() throws {
        let coordinator = try coordinator()
        let spellbook = try #require(coordinator.caster).spellbook
        let spell = SpellbookFixture.key(Self.grantingSpell)
        spellbook.learn(spell, on: .player)
        try spellbook.equip(spell, in: .right, on: .player)
        coordinator.weaponEnchantments.advanceEquipSlots(playerWeaponsDrawn: false)
        #expect(equipAbilities(on: coordinator) == [SpellbookFixture.key(Self.ability)])
        coordinator.weaponEnchantments.advanceEquipSlots(playerWeaponsDrawn: false)
        #expect(equipAbilities(on: coordinator).count == 1, "a second frame changes nothing")
        _ = spellbook.unequip(.right, on: .player)
        coordinator.weaponEnchantments.advanceEquipSlots(playerWeaponsDrawn: false)
        #expect(equipAbilities(on: coordinator).isEmpty)
    }

    @Test func aSpellWithNoEquipAbilityGrantsNothing() throws {
        let coordinator = try coordinator()
        let spellbook = try #require(coordinator.caster).spellbook
        let healing = SpellbookFixture.key(SpellbookFixture.Spell.healing)
        spellbook.learn(healing, on: .player)
        try spellbook.equip(healing, in: .left, on: .player)
        coordinator.weaponEnchantments.equipmentChanged(on: .player)
        #expect(equipAbilities(on: coordinator).isEmpty)
    }

    @Test func onlyAHostileSpellThatIsNoAbilityCausesPain() throws {
        let spells = try #require(try coordinator().caster).spellbook.spells
        let payload = { (id: UInt32) in
            spells.spell(key: SpellbookFixture.key(id))?.payload(caster: .player).causesPain
        }
        #expect(payload(SpellbookFixture.Spell.firebolt) == true)
        #expect(payload(SpellbookFixture.Spell.healing) == false)
        #expect(payload(Self.ability) == false)
    }

    private struct EnchantedSession {
        let coordinator: MagicCoordinator
        let equipment: FakeHandEquipment
        let world: FakeMagicWorld
    }

    private func enchantedSession() throws -> EnchantedSession {
        let file = try EnchantingFixture.plugin()
        let plugin = ActiveEffectFixture.pluginName
        let enchantments = EnchantmentStore(plugins: [(plugin, file)])
        let inventory = FakeInventory(baselines: InventoryBaselineResolver.build(
            from: file,
            enchantments: ItemEnchantmentResolver(store: enchantments, pluginName: plugin)
        ))
        try inventory.add(EnchantingFixture.fireSword, count: 1, to: .player)
        let equipment = FakeHandEquipment()
        equipment.worn = [EnchantingFixture.fireSword]
        let world = FakeMagicWorld()
        world.inventory = inventory
        world.equipment = equipment
        var data = MagicSessionData()
        data.effects = MagicEffectsData(
            values: FixedActorValues(),
            store: MagicEffectStore(plugins: [(plugin, file)]),
            pluginName: plugin,
            conditionRegistry: ConditionFunctionRegistry()
        )
        data.enchantments = enchantments
        return EnchantedSession(
            coordinator: MagicCoordinator(world: world, data: data), equipment: equipment,
            world: world
        )
    }

    private static func looks(in commands: [MagicCommand]) -> [(WeaponEnchantVisual, Bool)] {
        commands.compactMap {
            guard case let .weaponEnchantVisual(look, .player, shown) = $0 else { return nil }
            return (look, shown)
        }
    }

    @Test func aDrawnEnchantedWeaponShowsItsLookAndSheathingHidesIt() throws {
        let session = try enchantedSession()
        let coordinator = session.coordinator
        coordinator.weaponEnchantments.advanceEquipSlots(playerWeaponsDrawn: true)
        let shown = Self.looks(in: coordinator.frameStep.takeCommands())
        #expect(shown.map(\.1) == [true])
        let look = try #require(shown.first?.0)
        #expect(look.visuals == FormID(0x208), "the RFCT replaces the shader and the art")
        #expect(look.shader == nil && look.art == nil)
        coordinator.weaponEnchantments.advanceEquipSlots(playerWeaponsDrawn: true)
        #expect(Self.looks(in: coordinator.frameStep.takeCommands()).isEmpty)
        coordinator.weaponEnchantments.advanceEquipSlots(playerWeaponsDrawn: false)
        #expect(Self.looks(in: coordinator.frameStep.takeCommands()).map(\.1) == [false])
        session.equipment.worn = [EnchantingFixture.ironSword]
        #expect(coordinator.weaponEnchantments.weaponEnchantVisual(of: .player) == nil)
        let npc = ReferenceKey.plugin(name: "base.esm", objectID: 0x900)
        session.world.residents = [npc]
        session.world.drawnWeapons = [npc]
        coordinator.weaponEnchantments.advanceEquipSlots(playerWeaponsDrawn: false)
        #expect(Self.looks(in: coordinator.frameStep.takeCommands()).isEmpty, "no NPC weapon")
    }
}
