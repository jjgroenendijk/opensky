// A feature's string settings resolve by editor ID, and a missing one reads as its fallback.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

private enum SampleText: String, GameSettingTextKey {
    case greeting = "sSampleGreeting"
    case farewell = "sSampleFarewell"

    var fallback: String {
        self == .greeting ? "Hello" : "Goodbye"
    }
}

struct GameSettingTextsTests {
    @Test func aSetTextWinsAndAMissingOneFallsBack() throws {
        let store = try GameSettingFixture.store(["sSampleGreeting": .text("Well met")])
        let texts = GameSettingTexts<SampleText>.resolve(store: store) { text in
            guard case let .inline(value) = text.text else { return nil }
            return value
        }
        #expect(texts[.greeting] == "Well met")
        #expect(texts[.farewell] == "Goodbye")
        #expect(GameSettingTexts<SampleText>.vanilla[.greeting] == "Hello")
    }

    @Test func aTextTheStringsCannotResolveKeepsTheFallback() throws {
        let store = try GameSettingFixture.store(["sSampleGreeting": .text("Well met")])
        let texts = GameSettingTexts<SampleText>.resolve(store: store) { _ in nil }
        #expect(texts[.greeting] == "Hello")
    }
}
