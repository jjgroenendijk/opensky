// The inventory's recharge words without game data.

import OpenSkyGameData
import OpenSkyMenus
import Testing

struct RechargeTextTests {
    @Test func everyRechargeTextHasOpenSkysWords() {
        for key in RechargeText.allCases {
            #expect(!GameSettingTexts<RechargeText>.vanilla[key].isEmpty)
        }
    }
}
