import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorld
import OpenSkyWorldState
import Testing

struct BaseObjectScriptsRealDataTests {
    /// `CidhnaMineOre` has no `VMAD` of its own. Its ore vein script sits on its `ACTI` base.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func anOreVeinRunsItsBaseScript() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let lookup = PlacedRecordLookup(
            index: ESMFormIDIndex(file: file),
            resolver: FormIDResolver(pluginName: "Skyrim.esm", masters: []),
            localized: true
        )
        let entry = try #require(lookup.entry(for: .plugin(name: "skyrim.esm", objectID: 0x0EBC57)))
        #expect(entry.placedReference?.scriptData.scripts.isEmpty == true)
        #expect(entry.scripts.map(\.name) == ["MineOreScript"])
    }
}
