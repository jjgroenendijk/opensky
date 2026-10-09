// The Graphics page's data: the base game options, the presets, the texture
// budget rule, and the step from the schema 2 settings file. The INI text is
// written in code.

import Foundation
@testable import OpenSkyGameData
import Testing

@MainActor
struct GraphicsSettingsTests {
    private let mebibyte: UInt64 = 1 << 20

    private func file(_ text: String) -> INIFile {
        INIFile(data: Data(text.utf8))
    }

    private func option(_ key: String) throws -> GraphicsOption {
        try #require(GraphicsOptions.all.first { $0.key == key })
    }

    @Test func everyOptionHasOneIdAndAppliedOnesAreTheDistances() {
        let ids = GraphicsOptions.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        let applied = GraphicsOptions.all.filter { $0.unavailableReason == nil }.map(\.key)
        #expect(applied == [
            "fBlockLevel0Distance", "fBlockLevel1Distance", "fBlockMaximumDistance",
            "fTreeLoadDistance"
        ])
        #expect(GraphicsOptions.all.allSatisfy { $0.id.rawValue == "graphics.\($0.key)" })
    }

    @Test func aToggleReadsAsZeroOrOneAndJunkIsIgnored() throws {
        let toggle = try #require(GraphicsOptions.all.first { $0.isToggle })
        let text = "[\(toggle.section)]\n\(toggle.key)=7\n[TerrainManager]\nfTreeLoadDistance=abc\n"
        let trees = try option("fTreeLoadDistance")
        #expect(GraphicsOptions.value(toggle, in: file(text)) == 1)
        #expect(GraphicsOptions.value(trees, in: file(text)) == nil)
    }

    @Test func theINIGivesAnOptionItsDefault() throws {
        let trees = try option("fTreeLoadDistance")
        let ini = INISettings(sources: [INISettingsSource(
            name: "SkyrimPrefs.ini", file: file("[TerrainManager]\nfTreeLoadDistance=12345\n")
        )])
        let catalog = PlayerSettingsCatalog.vanilla.applyingINIDefaults(ini)
        #expect(catalog.definition(trees.id)?.defaultValue == 12345)
    }

    @Test func aPresetSetsItsValuesAndAnotherValueIsCustom() throws {
        let presets = GraphicsPresetFiles(files: [
            .medium: file("[TerrainManager]\nfBlockLevel0Distance=30000\n"),
            .ultra: file("[TerrainManager]\nfBlockLevel0Distance=60000\n")
        ])
        #expect(presets.values(.low).isEmpty)
        let store = PlayerSettingsStore(persistence: nil)
        presets.apply(.ultra, to: store)
        let near = try option("fBlockLevel0Distance")
        #expect(store.value(near.id) == 60000)
        #expect(store.value(.textureQuality) == 0)
        #expect(presets.current(in: store) == .ultra)
        store.set(near.id, to: 1000)
        #expect(presets.current(in: store) == nil)
    }

    @Test func automaticTakesAQuarterOfTheFreeWorkingSet() {
        #expect(TextureBudget.automaticBytes(
            workingSetBytes: 16 << 30, allocatedBytes: 4 << 30
        ) == 3 << 30)
        #expect(TextureBudget.automaticBytes(
            workingSetBytes: 1 << 30, allocatedBytes: 900 * mebibyte
        ) == TextureBudget.smallestBytes)
        #expect(TextureBudget.automaticBytes(
            workingSetBytes: 96 << 30, allocatedBytes: 0
        ) == TextureBudget.largestBytes)
        #expect(TextureBudget.automaticBytes(
            workingSetBytes: 4 << 30, allocatedBytes: 5 << 30
        ) == TextureBudget.smallestBytes)
        #expect(TextureBudget.automaticBytes(
            workingSetBytes: 3 * (1 << 30) + 100 * mebibyte, allocatedBytes: 0
        ) % (64 << 20) == 0)
    }

    @Test func aFixedChoiceIsItsMenuSize() {
        #expect(TextureBudget.choiceTitles.first == "Automatic")
        #expect(TextureBudget.bytes(choice: 3, workingSetBytes: 0, allocatedBytes: 0) == 512 << 20)
        #expect(TextureBudget
            .bytes(choice: 99, workingSetBytes: 0, allocatedBytes: 0) == 2048 << 20)
    }

    @Test func schemaTwoMovesTheBudgetAndRenamesTheAssetSettings() throws {
        let old = """
        {"schema": 2, "values": {"rendering.textureBudget": 2, "assetCache.preset": 0,
        "assetCache.limitGiB": 40, "assetCache.enabled": 0},
        "texts": {"assetCache.folder": "/Volumes/Fast/Cache"}}
        """
        let model = try PlayerSettingsModel(decoding: Data(old.utf8), catalog: .vanilla)
        #expect(model.values[.textureBudget] == 3)
        #expect(model.values[.textureQuality] == 2)
        #expect(model.values[PlayerSettingID("assetOptimisation.enabled")] == 0)
        #expect(model.texts[.assetOptimisationFolder] == "/Volumes/Fast/Cache")
    }
}
