// Quality names from the weapon and armour settings, and the names past the sixth level.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyInventoryInterface
import Testing

struct TemperingTextsTests {
    @Test func weaponsAndArmourReadTheirOwnNames() throws {
        let store = try GameSettingFixture.store([
            "sHealthDataPrefixWeap1": .text("Sharp"),
            "sHealthDataPrefixArmo1": .text("Sturdy")
        ])
        let texts = TemperingTexts.resolve(store: store) { text in
            guard case let .inline(value) = text else { return nil }
            return value
        }
        #expect(texts.name(level: 1, isWeapon: true) == "Sharp")
        #expect(texts.name(level: 1, isWeapon: false) == "Sturdy")
        #expect(texts.name(level: 2, isWeapon: true) == "Superior")
        #expect(texts.name(level: 0, isWeapon: true) == "plain")
        #expect(texts.name(level: 8, isWeapon: false) == "Legendary +2")
    }
}
