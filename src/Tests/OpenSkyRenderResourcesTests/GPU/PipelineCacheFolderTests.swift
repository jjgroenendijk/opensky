// The pipeline archive's name stamps the GPU and the shader library, so a change of
// either gives another file. No GPU is needed: the GPU is named by a string.

import Foundation
@testable import OpenSkyRenderResources
import Testing

struct PipelineCacheFolderTests {
    private static func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(
                path: "PipelineCacheFolderTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func theArchiveNameChangesWithTheGPUAndLivesInThePipelinesFolder() throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = folder.appending(path: "default.metallib")
        try Data([1, 2, 3]).write(to: library)
        let first = try #require(PipelineCacheFolder.archiveURL(
            inCacheFolder: folder, gpuName: "GPU A", shaderLibrary: library
        ))
        let second = try #require(PipelineCacheFolder.archiveURL(
            inCacheFolder: folder, gpuName: "GPU B", shaderLibrary: library
        ))
        #expect(first != second)
        #expect(first.pathExtension == "mtl4archive")
        #expect(first.deletingLastPathComponent().lastPathComponent == "pipelines")
    }

    @Test func noShaderLibraryGivesNoArchive() throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(PipelineCacheFolder.archiveURL(
            inCacheFolder: folder, gpuName: "GPU A", shaderLibrary: nil
        ) == nil)
        #expect(PipelineCacheFolder.archiveURL(
            inCacheFolder: folder, gpuName: "GPU A",
            shaderLibrary: folder.appending(path: "missing.metallib")
        ) == nil)
    }
}
