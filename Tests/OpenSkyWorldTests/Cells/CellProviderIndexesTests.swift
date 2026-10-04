import FormatsESMTesting
import Foundation
import Metal
import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyWorld
import Synchronization
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct CellProviderIndexesTests {
    @Test
    func buildsCompleteProviderFromSyntheticPlugin() async throws {
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
        let events = Mutex<[WorldLoadEvent]>([])
        let session = try await CellProviderIndexes.loadSession(
            root: root,
            fileSystem: fileSystem,
            device: device,
            localizationLanguage: "french",
            terrainLODConfigurationStore: .fallback(),
            progress: WorldLoadProgress { event in events.withLock { $0.append(event) } }
        )
        let provider = try #require(session.data as? WorldDataStores)
        var timeline = WorldLoadTimeline()
        for event in events.withLock(\.self) {
            timeline.apply(event)
        }
        // The app opens the archives itself, so only that stage stays pending.
        #expect(timeline.finishedCount == WorldLoadStage.allCases.count - 1)
        #expect(timeline.state(of: .archives) == .pending)

        #expect(provider.scriptFileSystem as? VirtualFileSystem === fileSystem)
        #expect(provider.scriptFormIDResolver.pluginName == "Skyrim.esm")
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

    @Test
    func cancelledLoadThrowsBeforeTheFirstStage() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let root = GameDataRoot(
            installURL: URL(filePath: "/nonexistent"),
            dataURL: URL(filePath: "/nonexistent/Data"),
            source: .environment
        )
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try await CellProviderIndexes.loadSession(
                root: root,
                fileSystem: VirtualFileSystem(dataURL: root.dataURL, archiveURLs: []),
                device: device,
                terrainLODConfigurationStore: .fallback()
            )
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
