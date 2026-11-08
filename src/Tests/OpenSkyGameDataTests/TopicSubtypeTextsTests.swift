// Topic subtype names: every code maps to a setting of its own, and a resolved
// setting names its code.

import OpenSkyEngineTesting
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct TopicSubtypeTextsTests {
    @Test func everyCodeHasItsOwnSetting() {
        let suffixes = TopicSubtypeTexts.settingSuffixes
        #expect(suffixes.count == 97)
        #expect(Set(suffixes.values).count == 97)
        #expect(suffixes["HELO"] == "MiscellaneousHello")
        #expect(suffixes["SCEN"] == "SceneDialogueCustom")
    }

    @Test func aResolvedSettingNamesItsCode() throws {
        let store = try GameSettingFixture.store([
            "sTopicSubtypeTextMiscellaneousHello": .text("Greeting")
        ])
        let texts = TopicSubtypeTexts.resolve(store: store) { text in
            guard case let .inline(value) = text.text else { return nil }
            return value
        }
        #expect(texts.name(of: "HELO") == "Greeting")
        #expect(texts.name(of: "FMAT") == "FMAT")
        #expect(texts.name(of: nil) == nil)
    }
}
