// The magic menu's spell card text: effect descriptions with their numbers filled in,
// and only the entries whose conditions hold for the player.

import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyGameData
@testable import OpenSkyMagic
import OpenSkyMagicFixtures
import OpenSkyMagicInterface
import Testing

@MainActor
struct MagicMenuSpellCardTests {
    private static func wired(effects: Bool) throws -> MagicCoordinator {
        var data = MagicSessionData()
        data.casting = try MagicCastingData(
            spellbook: SpellbookFixture.runtime().0,
            values: FixedActorValues(),
            spellPluginName: SpellbookFixture.pluginName,
            baselines: nil
        )
        if effects {
            data.effects = try MagicEffectsData(
                values: FixedActorValues(),
                store: SpellbookFixture.effectStore(index: SpellbookFixture.index()),
                pluginName: SpellbookFixture.pluginName,
                conditionRegistry: ConditionFunctionRegistry()
            )
        }
        return MagicCoordinator(world: FakeMagicWorld(), data: data)
    }

    private static func cards(_ coordinator: MagicCoordinator) throws -> [String: String] {
        let caster = try #require(coordinator.caster)
        caster.spellbook.grant(
            [SpellbookFixture.Spell.healing, SpellbookFixture.Spell.wardedHeal]
                .map(SpellbookFixture.key),
            to: .player
        )
        return Dictionary(uniqueKeysWithValues: coordinator.magicMenu.magicMenuSpells.map {
            ($0.name, $0.card?.effects ?? "")
        })
    }

    @Test func anEffectShowsItsDescriptionWithTheNumbersFilledIn() throws {
        let cards = try Self.cards(Self.wired(effects: true))
        #expect(cards["Healing"] == "Heals 10 points over 1 s. Restoration")
    }

    @Test func anEntryWhoseConditionsFailIsLeftOut() throws {
        let cards = try Self.cards(Self.wired(effects: true))
        #expect(cards["WardedHeal"] == "Heals 15 points over 3 s. Restoration")
    }

    @Test func withoutAnEffectRuntimeEveryEntryShows() throws {
        let cards = try Self.cards(Self.wired(effects: false))
        #expect(cards["WardedHeal"] == "Heals 15 points over 3 s. Restoration FortifyResistFire 25")
    }
}
