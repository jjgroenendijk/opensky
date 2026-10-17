// Crafting experience: UESP's making formula, the measured improving formula, and
// the settings that replace the defaults. UESP "Skyrim:Leveling".

import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct CraftingSkillUseSettingsTests {
    @Test func makingFollowsTheUESPFormula() {
        let settings = CraftingSkillUseSettings.vanilla
        // item quantity × (25 + 3 × value^0.65): a value of 100 gives 25 + 3 × 19.95.
        #expect(abs(settings.constructed(value: 100, count: 1) - 84.86) < 0.01)
        #expect(abs(settings.constructed(value: 100, count: 3) - 3 * 84.86) < 0.03)
        #expect(settings.constructed(value: 0, count: 2) == 50)
    }

    @Test func improvingGrowsWithTheRootOfTheGainAndTheLevels() {
        let settings = CraftingSkillUseSettings.vanilla
        #expect(abs(settings.tempered(valueGain: 100, levels: 1) - 38) < 0.001)
        #expect(abs(settings.tempered(valueGain: 100, levels: 4) - 76) < 0.001)
        #expect(settings.tempered(valueGain: 0, levels: 1) == 0)
    }

    @Test func theInstallSettingsReplaceTheDefaults() throws {
        let store = try GameSettingFixture.store([
            "fConstructibleSkillUseConst": .float(10),
            "fConstructibleSkillUseMult": .float(2),
            "fConstructibleSkilluseExp": .float(1),
            "fTemperingSkillUseMult": .float(0.5)
        ])
        let settings = CraftingSkillUseSettings.resolve(store: store)
        #expect(settings.constructed(value: 20, count: 1) == 50)
        #expect(abs(settings.tempered(valueGain: 100, levels: 1) - 19) < 0.001)
    }
}
