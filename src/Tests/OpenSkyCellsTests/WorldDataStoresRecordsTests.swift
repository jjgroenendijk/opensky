// The loaded world data answers the records port with the stores it holds.

import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import Testing

struct WorldDataStoresRecordsTests {
    @Test func storesTheWorldHasNotLoadedAreMissing() {
        let records: any WorldRecordsPort = WorldDataStores(
            scriptFormIDResolver: FormIDResolver(pluginName: "Base.esm", masters: [])
        )
        #expect(records.locationKeywords == nil)
        #expect(records.leveledScriptEdits == nil)
        #expect(records.questStore == nil)
    }
}
