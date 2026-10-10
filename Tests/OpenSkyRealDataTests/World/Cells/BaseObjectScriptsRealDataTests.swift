import Foundation
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
            index: LoadOrderRecordIndex(plugins: [("Skyrim.esm", file)])
        )
        let entry = try #require(lookup.entry(for: .plugin(name: "skyrim.esm", objectID: 0x0EBC57)))
        #expect(entry.placedReference?.scriptData.scripts.isEmpty == true)
        #expect(entry.scripts.map(\.name) == ["MineOreScript"])
    }

    /// The fishing plugin places a plaque with its own script in a `HearthFires.esm` house.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func aCreationClubReferenceIsFoundWithItsScript() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let fish = "ccBGSSSE001-Fish.esm"
        try #require(plugins.contains { $0.name.caseInsensitiveCompare(fish) == .orderedSame })
        let lookup = PlacedRecordLookup(index: LoadOrderRecordIndex(plugins: plugins))
        let key = ReferenceKey.plugin(name: fish.lowercased(), objectID: 0x05C617)
        let entry = try #require(lookup.entry(for: key))
        #expect(entry.scripts.map(\.name).contains("ccBGSSSE001_FishPlaqueScript"))
        #expect(lookup.interiorCell(holding: entry.formID) != nil)
    }
}
