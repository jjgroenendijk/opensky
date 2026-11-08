// Env-gated KYWD/KWDA resolution sweep over the user's read-only load order.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct KeywordStoreRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func resolvesPinnedItemsAndMeasuresEveryKeywordReference() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let store = KeywordStore(plugins: plugins)
        let skyrim = try #require(
            plugins.first {
                $0.name.caseInsensitiveCompare("Skyrim.esm") == .orderedSame
            }
        )

        try expectKeywords(
            ["WeapMaterialIron", "WeapTypeSword", "VendorItemWeapon"],
            on: "IronSword",
            in: skyrim.file,
            pluginName: skyrim.name,
            store: store
        )
        try expectKeywords(
            ["ArmorHeavy", "ArmorMaterialIron", "ArmorCuirass", "VendorItemArmor"],
            on: "ArmorIronCuirass",
            in: skyrim.file,
            pluginName: skyrim.name,
            store: store
        )
        try expectKeywords(
            ["VendorItemClutter"],
            on: "Gold001",
            in: skyrim.file,
            pluginName: skyrim.name,
            store: store
        )

        var referenced: Set<ResolvedFormID> = []
        for plugin in plugins {
            ESMWalk.forEachRecord(in: plugin.file) { record in
                guard let fields = try? record.fields() else { return true }
                for field in fields where field.type == "KWDA" {
                    var list = KeywordList()
                    guard (try? list.decode(field: field)) == true else { continue }
                    for rawID in list.keywords {
                        if let id = store.resolvedID(rawID, fromPlugin: plugin.name) {
                            referenced.insert(id)
                        }
                    }
                }
                return true
            }
        }
        let resolvedCount = referenced.count { store.keyword($0) != nil }
        let unresolvedCount = referenced.count - resolvedCount

        #expect(referenced.count >= 843)
        #expect(resolvedCount >= 843)
        #expect(unresolvedCount == 0)
        print(
            "[INFO] KWDA distinct references \(referenced.count), "
                + "resolved \(resolvedCount), unresolved \(unresolvedCount)"
        )
    }

    private func expectKeywords(
        _ expected: [String],
        on editorID: String,
        in file: ESMFile,
        pluginName: String,
        store: KeywordStore
    ) throws {
        let record = try #require(ESMWalk.record(withEditorID: editorID, in: file))
        var list = KeywordList()
        for field in try record.fields() {
            _ = try list.decode(field: field)
        }
        #expect(list.displayStrings(fromPlugin: pluginName, using: store) == expected)
    }
}
