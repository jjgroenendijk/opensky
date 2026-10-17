// The skill multiplier on a spell's cost: UESP's ~0.5939 at skill 100 for the player.

import OpenSkyEngineTesting
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct SpellCostSettingsTests {
    @Test func skillLowersThePlayersCostAsUESPMeasures() {
        let settings = SpellCostSettings.vanilla
        #expect(settings.skillMultiplier(skill: 0, isPlayer: true) == 1)
        #expect(abs(settings.skillMultiplier(skill: 100, isPlayer: true) - 0.5939) < 0.0005)
        #expect(settings.skillMultiplier(skill: 10000, isPlayer: true) == 0)
        #expect(abs(settings.skillMultiplier(skill: 100, isPlayer: false) - 0.6464) < 0.0005)
    }

    @Test func theSettingsReplaceTheDefaults() throws {
        let store = try GameSettingFixture.store([
            "fMagicCasterPCSkillCostBase": .float(0),
            "fMagicSkillCostScale": .float(1)
        ])
        let settings = SpellCostSettings.resolve(store: store)
        #expect(settings.skillMultiplier(skill: 100, isPlayer: true) == 1)
        #expect(abs(settings.skillMultiplier(skill: 100, isPlayer: false) - 0.75) < 0.0001)
    }
}
