// Crime names from the `sCrimeType*` settings, and the bounty counts that use them.

import OpenSkyCrimeInterface
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct CrimeTextsTests {
    @Test func theSettingsNameEachCountedCrime() throws {
        let store = try GameSettingFixture.store([
            "sCrimeTypeSteal": .text("Steal"),
            "sCrimeTypeAttack": .text("Attack")
        ])
        let texts = CrimeTexts.resolve(store: store) { text in
            guard case let .inline(value) = text.text else { return nil }
            return value
        }
        #expect(texts.name(of: .theft) == "Steal")
        #expect(texts.name(of: .assault) == "Attack")
        #expect(texts.name(of: .murder) == "murder")
    }
}
