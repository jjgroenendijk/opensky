// The magic menu's shout words without game data, and the refusal list of a spell hit.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import Testing

struct ShoutMenuTextTests {
    @Test func everyShoutTextHasOpenSkysWords() {
        for key in ShoutMenuText.allCases {
            #expect(!GameSettingTexts<ShoutMenuText>.vanilla[key].isEmpty)
        }
    }

    @Test func aRefusedTargetIsListedInTheReport() {
        var report = SpellHitReport()
        let refusal = SpellTargetRefusal(target: .player, aboveLevelCap: true, nothingLanded: true)
        report.noteRefusal(refusal)
        #expect(report.refusals == [refusal])
    }
}
