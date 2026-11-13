// The command-mode crosshair words without game data.

import OpenSkyAIPackages
import OpenSkyGameData
import Testing

struct FollowerCommandTextTests {
    @Test func everyFollowerOrderHasOpenSkysWords() {
        for key in FollowerCommandText.allCases {
            #expect(!GameSettingTexts<FollowerCommandText>.vanilla[key].isEmpty)
        }
    }
}
