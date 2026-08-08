import Foundation
import Metal
@testable import opensky
import Testing

struct CellProviderIndexesTests {
    @Test
    @MainActor
    func buildsCompleteProviderFromSyntheticPlugin() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let installURL = FileManager.default.temporaryDirectory.appending(
            path: "CellProviderIndexesTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let dataURL = installURL.appending(path: "Data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: installURL) }
        try ESMFixture.tes4().write(to: dataURL.appending(path: "Skyrim.esm"))

        let root = GameDataRoot(
            installURL: installURL,
            dataURL: dataURL,
            source: .environment
        )
        let fileSystem = VirtualFileSystem(dataURL: dataURL, archiveURLs: [])
        let indexes = try CellProviderIndexes(
            root: root,
            fileSystem: fileSystem,
            device: device,
            terrainLODConfigurationStore: .fallback()
        )
        let provider = indexes.makeProvider()

        #expect(provider.builder.fileSystem === fileSystem)
        #expect(provider.worldspaceEditorID == FirstRenderCell.worldspaceEditorID)
        #expect(provider.weatherSystem == nil)
        #expect(provider.soundStore != nil)
        #expect(provider.aspcStore != nil)
        #expect(provider.musicStore != nil)
        #expect(provider.globalStore != nil)
        #expect(provider.dialogueStore != nil)
        #expect(provider.inventoryBaselines != nil)
        #expect(provider.equipmentCatalog != nil)
        #expect(provider.movementConfiguration.walkSpeed.value == 100)
        #expect(provider.movementConfiguration.runSpeed.value == 370)
    }
}
