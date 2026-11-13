// The name of an item whose record has none, from `sMissingName`.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyInventory
import Testing

struct MissingNameTests {
    @Test func theInstallWordReplacesOpenSkysWord() throws {
        let store = try GameSettingFixture.store(["sMissingName": .text("<Nameless>")])
        let name = InventoryTexts.missingName(store: store) { text in
            guard case let .inline(value) = text.text else { return nil }
            return value
        }
        #expect(name == "<Nameless>")
        #expect(InventoryTexts.missingName(store: store) == "<Missing Name>")
    }
}
