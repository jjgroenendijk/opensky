// Soul names from the soul level settings, and the filled and empty gem lines.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct SoulTextsTests {
    @Test func aGemNamesItsSoulOrSaysItIsEmpty() throws {
        let store = try GameSettingFixture.store([
            "sSoulLevelNamePetty": .text("Tiny"),
            "sSoulLevel": .text("Holds a %s soul")
        ])
        let texts = SoulTexts.resolve(store: store) { text in
            guard case let .inline(value) = text.text else { return nil }
            return value
        }
        #expect(texts.contents(.petty) == "Holds a Tiny soul")
        #expect(texts.contents(.empty) == "Empty")
        #expect(texts.contents(nil) == "Empty")
        #expect(texts.name(of: .grand) == "Grand")
    }
}
