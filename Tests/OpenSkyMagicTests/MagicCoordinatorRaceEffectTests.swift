// Which race spells give an actor a lasting look. Records are synthetic and
// built in code, never extracted game files.

import FeaturesTesting
import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
import OpenSkyMagicFixtures
@testable import OpenSkyMagicInterface
import Testing

@MainActor
struct MagicCoordinatorRaceEffectTests {
    private static let nord: UInt32 = 0x0900
    private static let villager: UInt32 = 0x0901

    /// A race power, such as Dragonskin, shows its look only while it is cast.
    /// Only the race's abilities give a lasting one.
    @Test func onlyTheRacesAbilitiesGiveALastingLook() throws {
        let index = try SpellbookFixture.index()
        let coordinator = MagicCoordinator()
        coordinator.attach(world: FakeMagicWorld())
        coordinator.wireEffects(
            values: FixedActorValues(),
            store: SpellbookFixture.effectStore(index: index),
            pluginName: SpellbookFixture.pluginName,
            conditionRegistry: ConditionFunctionRegistry()
        )
        let spells = [SpellbookFixture.Spell.dragonskin, SpellbookFixture.Spell.resistFire]
        try coordinator.wireCasting(
            spellbook: SpellbookFixture.runtime().0,
            values: FixedActorValues(),
            spellPluginName: SpellbookFixture.pluginName,
            baselines: ActorSpellFixture.resolver(
                npcs: [ActorSpellFixture.npc(formID: Self.villager, race: Self.nord)],
                races: [ActorSpellFixture.race(formID: Self.nord, spells: spells)]
            )
        )
        let links = coordinator.raceEffectLinks(
            base: FormID(Self.villager), actor: SpellbookFixture.key(Self.villager)
        )
        // Resist Fire has two entries; Dragonskin's entries are left out.
        #expect(links.count == 2)
    }
}
