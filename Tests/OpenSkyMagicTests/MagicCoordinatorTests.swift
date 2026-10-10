// The magic shell over a fake world: what it reads, what it forwards, and the
// state it keeps. The rules are tested in `MagicCoreTests`. Records are
// synthetic and built in code, never extracted game files.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyInventoryInterface
@testable import OpenSkyMagic
import OpenSkyMagicFixtures
@testable import OpenSkyMagicInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct MagicCoordinatorTests {
    private static func effectsWired(_ world: FakeMagicWorld) throws -> MagicCoordinator {
        let file = try ActiveEffectFixture.plugin(records: ActiveEffectFixture.effectRecords)
        let coordinator = MagicCoordinator()
        coordinator.attach(world: world)
        coordinator.wireEffects(
            values: FixedActorValues(),
            store: MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)]),
            pluginName: ActiveEffectFixture.pluginName,
            conditionRegistry: ConditionFunctionRegistry()
        )
        return coordinator
    }

    private static func castingWired(_ world: FakeMagicWorld) throws -> MagicCoordinator {
        let coordinator = MagicCoordinator()
        coordinator.attach(world: world)
        try coordinator.wireCasting(
            spellbook: SpellbookFixture.runtime().0,
            values: FixedActorValues(),
            spellPluginName: SpellbookFixture.pluginName,
            baselines: nil
        )
        return coordinator
    }

    @Test func anUnwiredCoordinatorReportsItselfUnavailable() {
        let coordinator = MagicCoordinator()
        #expect(coordinator.magicEffectControlSnapshot == .unavailable)
        #expect(coordinator.castingControlSnapshot == .unavailable)
        #expect(coordinator.dispelPlayerMagicEffects() == MagicCore.effectsUnavailableText)
        #expect(coordinator.consumeFirstCarriedMagicItem() == MagicCore.effectsUnavailableText)
        #expect(coordinator.castReadiedSpell(in: .right) == MagicCore.castingUnavailableText)
        #expect(!coordinator.hasReadiedSpell(in: .right))
        #expect(coordinator.magicConditionResolution().state(of: .player) == nil)
        #expect(coordinator.withEffects { _ in true } == nil)
        #expect(coordinator.enchantmentProfile(of: FormID(1)) == nil)
    }

    /// Under one 1/60 s step, so the whole delta stays in the accumulator. A
    /// tick that changed a throwaway copy would leave it at zero.
    @Test func tickingCarriesTheRemainderInTheAccumulator() throws {
        let coordinator = try Self.effectsWired(FakeMagicWorld())
        coordinator.advanceEffects(delta: 0.004)
        #expect(coordinator.accumulator > 0.003)
        #expect(coordinator.accumulator < 0.005)
        coordinator.advanceEffects(delta: 0.02)
        #expect(coordinator.accumulator < ActiveEffectRuntime.fixedStepSeconds)
        #expect(coordinator.accumulator > 0)
    }

    @Test func tickingWithoutARuntimeDoesNothing() {
        let coordinator = MagicCoordinator()
        coordinator.advanceEffects(delta: 0.004)
        #expect(coordinator.accumulator == 0)
    }

    @Test func dispellingAnUntouchedPlayerSaysSo() throws {
        let coordinator = try Self.effectsWired(FakeMagicWorld())
        #expect(coordinator.dispelPlayerMagicEffects() == "No effect was acting on the player.")
        #expect(coordinator.magicEffectControlSnapshot.isAvailable)
    }

    @Test func consumingWithoutAnInventoryIsRefused() throws {
        let coordinator = try Self.effectsWired(FakeMagicWorld())
        #expect(coordinator.consumeMagicItem(FormID(1))
            == MagicCore.effectsUnavailableText)
    }

    @Test func theCastLoopReadsTheClockAndAimThroughTheWorld() throws {
        let world = FakeMagicWorld()
        let coordinator = try Self.castingWired(world)
        world.gameDaysPassed = 3.7
        #expect(coordinator.castingGameDay == 3)
        world.aim = SpellAim(target: .player)
        #expect(coordinator.aimedSpellTarget(within: 250, for: .player).target == .player)
        #expect(world.aimRequests.map(\.range) == [250])
    }

    @Test func onlyThePlayersCastFiresTheCastEventAtTheAimedTarget() throws {
        let world = FakeMagicWorld()
        let coordinator = try Self.castingWired(world)
        let recorder = StoryEventRecorder()
        coordinator.storyEvents = recorder
        let target = ReferenceKey.plugin(name: SpellbookFixture.pluginName, objectID: 0x900)
        world.aim = SpellAim(target: target)
        let flames = SpellbookFixture.key(SpellbookFixture.Spell.flames)

        coordinator.spellWasCast(flames, by: target)
        coordinator.spellWasCast(flames, by: .player)

        let cast = recorder.events("CAST")
        #expect(cast.map(\.actor1) == [.player])
        #expect(cast.first?.actor2 == target)
        #expect(cast.first?.form == StoryEventData.form(of: flames))
    }

    @Test func selectionCyclesOverTheKnownSpells() throws {
        let coordinator = try Self.castingWired(FakeMagicWorld())
        #expect(coordinator.selectNextKnownSpell() == "The player knows no spells to select.")
        let spells = [SpellbookFixture.Spell.healing, SpellbookFixture.Spell.flames]
        let caster = try #require(coordinator.caster)
        caster.spellbook.grant(spells.map(SpellbookFixture.key), to: .player)
        let known = coordinator.playerKnownSpells().map(\.displayName)
        #expect(known.count == 2)
        coordinator.selectNextKnownSpell()
        #expect(coordinator.selectedKnownSpell()?.displayName == known[1])
        coordinator.selectNextKnownSpell()
        #expect(coordinator.selectedKnownSpell()?.displayName == known[0])
    }

    /// The equip path: a spell readied in the right hand, then a one-handed sword
    /// equipped there. The equip change takes the spell out of that hand.
    @Test func equippingAWeaponReleasesTheSpellReadiedInItsHand() throws {
        let world = FakeMagicWorld()
        let equipment = FakeHandEquipment()
        world.equipment = equipment
        let coordinator = MagicCoordinator()
        coordinator.attach(world: world)
        try coordinator.wireCasting(
            spellbook: SpellbookFixture.runtime(equipment: equipment).0,
            values: FixedActorValues(),
            spellPluginName: SpellbookFixture.pluginName,
            baselines: nil
        )
        let spellbook = try #require(coordinator.caster).spellbook
        let healing = SpellbookFixture.key(SpellbookFixture.Spell.healing)
        spellbook.learn(healing, on: .player)
        try spellbook.equip(healing, in: .right, on: .player)

        equipment.worn = [FakeHandEquipment.oneHandedSword]
        coordinator.equipmentChanged(on: .player)

        #expect(spellbook.state(of: .player).rightHand == nil)
    }

    @Test func theConditionSeamCoversThePlayerAndResidents() throws {
        let world = FakeMagicWorld()
        let guardKey = ReferenceKey.generated(7)
        world.residents = [guardKey, .player]
        let coordinator = try Self.castingWired(world)
        let resolution = coordinator.magicConditionResolution()
        #expect(resolution.state(of: .player) != nil)
        #expect(resolution.state(of: guardKey) != nil)
        let lines = coordinator.castingControlSnapshot.conditionLines
        #expect(lines.count == 8)
        #expect(world.probedFunctions == [214, 223, 264, 570, 571, 572, 632, 699])
        #expect(lines.first == "HasMagicEffect(first effect of no readied spell) -> probed")
    }
}
