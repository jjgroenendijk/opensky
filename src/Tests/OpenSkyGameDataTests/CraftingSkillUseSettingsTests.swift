// Crafting experience: UESP's making formula, the improving formula, and
// the settings that replace the defaults. UESP "Skyrim:Leveling".

import OpenSkyEngineTesting
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

    @Test func improvingScalesWithTheConditionGainAndTheValue() {
        let settings = CraftingSkillUseSettings.vanilla
        // 0.1 condition x (100^0.6 x 8 + 25) = 0.1 x (15.849 x 8 + 25) = 15.18.
        #expect(abs(settings.tempered(value: 100, levels: 1) - 15.179) < 0.01)
        #expect(abs(settings.tempered(value: 100, levels: 4) - 4 * 15.179) < 0.04)
        // A worthless item counts as value 1: 0.1 x (8 + 25).
        #expect(abs(settings.tempered(value: 0, levels: 1) - 3.3) < 0.001)
        #expect(settings.tempered(value: 100, levels: 0) == 0)
    }

    @Test func theInstallSettingsReplaceTheDefaults() throws {
        let store = try GameSettingFixture.store([
            "fConstructibleSkillUseConst": .float(10),
            "fConstructibleSkillUseMult": .float(2),
            "fConstructibleSkilluseExp": .float(1),
            "fTemperingSkillUseMult": .float(0.5),
            "fTemperingSkillUseItemValConst": .float(0),
            "fTemperingSkillUseItemValMult": .float(1),
            "fTemperingSkillUseItemValExp": .float(1),
            "fHealthDataValue1": .float(1.5)
        ])
        let settings = CraftingSkillUseSettings.resolve(store: store)
        #expect(settings.constructed(value: 20, count: 1) == 50)
        // 0.5 condition x 0.5 x 100.
        #expect(abs(settings.tempered(value: 100, levels: 1) - 25) < 0.001)
    }
}
