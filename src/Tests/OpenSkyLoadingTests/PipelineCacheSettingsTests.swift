// The player settings decide whether the pipeline cache keeps an archive file, and the
// asset cache folder setting places it.

import Foundation
import OpenSkyAssetCache
import OpenSkyGameData
import OpenSkyLoading
import OpenSkyRenderResources
import Testing

@MainActor
struct PipelineCacheSettingsTests {
    private static func store(cacheOn: Bool, folder: URL) -> PlayerSettingsStore {
        let store = PlayerSettingsStore(persistence: nil)
        AssetCacheSettings(folder: folder).save(to: store)
        store.set(.pipelineCacheEnabled, to: cacheOn ? 1 : 0)
        return store
    }

    @Test func theArchiveLivesInTheCacheFolderOnlyWhenTheSettingIsOn() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(
                path: "PipelineCacheSettingsTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = folder.appending(path: "default.metallib")
        try Data([1, 2, 3]).write(to: library)

        let on = PipelineCache.archiveURL(
            gpuName: "GPU A", store: Self.store(cacheOn: true, folder: folder),
            shaderLibrary: library
        )
        #expect(on?.deletingLastPathComponent().lastPathComponent == "pipelines")
        #expect(PipelineCache.archiveURL(
            gpuName: "GPU A", store: Self.store(cacheOn: false, folder: folder),
            shaderLibrary: library
        ) == nil)
    }
}
