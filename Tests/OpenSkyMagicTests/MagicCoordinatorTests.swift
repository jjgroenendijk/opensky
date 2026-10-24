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
import OpenSkyProgressionInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct MagicCoordinatorTests {
    private static func effectsWired(_ world: FakeMagicWorld) throws -> MagicCoordinator {
        let file = try ActiveEffectFixture.plugin(records: ActiveEffectFixture.effectRecords)
        var data = MagicSessionData()
        data.effects = MagicEffectsData(
            values: FixedActorValues(),
            store: MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)]),
            pluginName: ActiveEffectFixture.pluginName,
            conditionRegistry: ConditionFunctionRegistry()
        )
        return MagicCoordinator(world: world, data: data)
    }

    private static func castingWired(
        _ world: FakeMagicWorld, storyEvents: StoryEventRecorder? = nil
    ) throws -> MagicCoordinator {
        var data = MagicSessionData()
        data.casting = try MagicCastingData(
            spellbook: SpellbookFixture.runtime().0,
            values: FixedActorValues(),
            spellPluginName: SpellbookFixture.pluginName,
            baselines: nil
        )
        return MagicCoordinator(world: world, data: data, storyEvents: storyEvents)
    }

    @Test func anUnwiredCoordinatorReportsItselfUnavailable() {
        let coordinator = MagicCoordinator(world: FakeMagicWorld())
        #expect(coordinator.magicEffectControlSnapshot == .unavailable)
        #expect(coordinator.castingControlSnapshot == .unavailable)
        #expect(coordinator.dispelPlayerMagicEffects().text == MagicCore.effectsUnavailableText)
        #expect(coordinator.consumeFirstCarriedMagicItem().text == MagicCore.effectsUnavailableText)
        #expect(coordinator.castReadiedSpell(in: .right).text == MagicCore.castingUnavailableText)
        #expect(!coordinator.hasReadiedSpell(in: .right))
        #expect(coordinator.magicConditionResolution().state(of: .player) == nil)
        #expect(coordinator.withEffects { _ in true } == nil)
        #expect(coordinator.enchantmentProfile(of: FormID(1)) == nil)
    }

    /// Under one 1/60 s step, so the whole delta stays in the accumulator. A
    /// tick that changed a throwaway copy would leave it at zero.
    @Test func tickingCarriesTheRemainderInTheAccumulator() throws {
        let coordinator = try Self.effectsWired(FakeMagicWorld())
        _ = coordinator.advanceEffects(delta: 0.004)
        #expect(coordinator.accumulator > 0.003)
        #expect(coordinator.accumulator < 0.005)
        _ = coordinator.advanceEffects(delta: 0.02)
        #expect(coordinator.accumulator < ActiveEffectRuntime.fixedStepSeconds)
        #expect(coordinator.accumulator > 0)
    }

    @Test func tickingWithoutARuntimeDoesNothing() {
        let coordinator = MagicCoordinator(world: FakeMagicWorld())
        _ = coordinator.advanceEffects(delta: 0.004)
        #expect(coordinator.accumulator == 0)
    }

    @Test func dispellingAnUntouchedPlayerSaysSo() throws {
        let coordinator = try Self.effectsWired(FakeMagicWorld())
        #expect(coordinator.dispelPlayerMagicEffects()
            .text == "No effect was acting on the player.")
        #expect(coordinator.magicEffectControlSnapshot.isAvailable)
    }

    @Test func consumingWithoutAnInventoryIsRefused() throws {
        let coordinator = try Self.effectsWired(FakeMagicWorld())
        #expect(coordinator.consumeMagicItem(FormID(1)).text
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
        let recorder = StoryEventRecorder()
        let coordinator = try Self.castingWired(world, storyEvents: recorder)
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
        #expect(coordinator.selectNextKnownSpell().text == "The player knows no spells to select.")
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
        var data = MagicSessionData()
        data.casting = try MagicCastingData(
            spellbook: SpellbookFixture.runtime(equipment: equipment).0,
            values: FixedActorValues(),
            spellPluginName: SpellbookFixture.pluginName,
            baselines: nil
        )
        let coordinator = MagicCoordinator(world: world, data: data)
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

    /// The caster's magnitude and duration perks and the target's incoming perk all
    /// scale a cast spell's entries.
    @Test func spellPerksScaleTheEntriesACastLands() throws {
        let world = FakeMagicWorld()
        world.perkFactors[.modSpellMagnitude] = 1.5
        world.perkFactors[.modIncomingSpellMagnitude] = 0.5
        world.perkFactors[.modSpellDuration] = 2
        let coordinator = try Self.castingWired(world)
        let firebolt = SpellbookFixture.key(SpellbookFixture.Spell.firebolt)
        let spell = try #require(coordinator.caster?.spellbook.spells.spell(key: firebolt))
        let target = ReferenceKey.generated(7)

        let scaled = coordinator.perkScaled(
            spell.record.effects, of: firebolt, caster: .player, on: target
        )

        let authored = try #require(spell.record.effects.first)
        #expect(scaled.first?.magnitude == authored.magnitude * 0.75)
        #expect(scaled.first?.duration == authored.duration * 2)
        #expect(world.perkOwners[.modSpellMagnitude] == .player)
        #expect(world.perkOwners[.modIncomingSpellMagnitude] == target)
    }

    @Test func potionsTakeTheDrinkersSpellPerksButNotIncomingOnes() throws {
        let world = FakeMagicWorld()
        world.perkFactors[.modSpellMagnitude] = 1.5
        world.perkFactors[.modSpellDuration] = 1.5
        world.perkFactors[.modIncomingSpellMagnitude] = 0.5
        let coordinator = try Self.effectsWired(world)
        let potion = ReferenceKey.plugin(name: "base.esm", objectID: 0x500)
        let entry = MagicItemEffect(
            effect: FormID(ActiveEffectFixture.restoreHealth), magnitude: 20, area: 0,
            duration: 10, conditions: ConditionList()
        )

        let scaled = coordinator.perkScaledPotion(
            [entry], of: potion, fromPlugin: ActiveEffectFixture.pluginName, drinker: .player
        )

        #expect(scaled.first?.magnitude == 30)
        #expect(scaled.first?.duration == 15)
        #expect(world.perkOwners[.modSpellMagnitude] == .player)
        #expect(world.perkOwners[.modIncomingSpellMagnitude] == nil)
    }

    @Test func aSkillBookRaisesItsSkillOnceWithThePerkPoints() throws {
        let world = FakeMagicWorld()
        world.perkFactors[.adjustBookSkillPoints] = 2
        let coordinator = try Self.castingWired(world)
        let book = FormID(0x0700)

        coordinator.readSkillBook(book, skill: 12)
        #expect(coordinator.readSkillBook(book, skill: 12).text.hasSuffix("was already read."))

        #expect(world.bookRaises.map(\.skill) == [12])
        #expect(world.bookRaises.map(\.points) == [2])
    }
}
