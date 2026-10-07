// The pipeline archive: a second renderer loads every pipeline the first one saved,
// and a corrupt file falls back to a compile. Needs Metal 4.

import EngineTesting
import Foundation
import Metal
@testable import OpenSkyRendering
import TagsTesting
import Testing

@Suite(.tags(.gpu))
@MainActor
struct PipelineCacheTests {
    private static let size = 32

    private func makeRenderer(archive: URL) throws -> Renderer {
        let device = try #require(OffscreenRendererFixture.device)
        return try Renderer(
            rendering: OffscreenRendererFixture.pausedView(
                device: device, width: Self.size, height: Self.size
            ),
            shaderLibrary: ShaderLibraryFixture.library(device: device),
            pipelineCache: PipelineCache(device: device, fileURL: archive)
        )
    }

    private func temporaryArchive() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "PipelineCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return folder.appending(path: "test.mtl4archive")
    }

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func aSecondLaunchCompilesNothing() throws {
        let archive = try temporaryArchive()
        defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }

        let first = try makeRenderer(archive: archive).pipelineCache.stats
        #expect(first.archive == .missing)
        #expect(first.misses > 0 && first.hits == 0)
        #expect(first.saved)

        let second = try makeRenderer(archive: archive).pipelineCache.stats
        #expect(second.archive == .loaded)
        #expect(second.hits == first.misses, "loaded \(second.hits) of \(first.misses)")
        #expect(second.misses == 0)
        #expect(!second.saved)
    }

    /// The archive is first saved whole, then damaged, so the checksum beside it is real.
    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func aCorruptArchiveFallsBackToACompile() throws {
        let archive = try temporaryArchive()
        defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }
        _ = try makeRenderer(archive: archive)
        var bytes = try Data(contentsOf: archive)
        bytes.replaceSubrange(0 ..< min(64, bytes.count), with: Data(repeating: 0xAB, count: 64))
        try bytes.write(to: archive)

        let renderer = try makeRenderer(archive: archive)
        let stats = renderer.pipelineCache.stats
        #expect(stats.archive == .unreadable)
        #expect(stats.hits == 0 && stats.misses > 0)
        #expect(stats.saved, "the rebuilt archive replaces the corrupt one")
        _ = try OffscreenRendererFixture.render(renderer, width: Self.size, height: Self.size)
    }

    @Test func clearingKeepsOnlyTheNamedArchive() throws {
        let folder = try temporaryArchive().deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["a.mtl4archive", "a.mtl4archive.sha256", "b.mtl4archive", "notes.txt"] {
            try Data([1]).write(to: folder.appending(path: name))
        }
        #expect(try PipelineCacheFolder.clear(folder: folder, keeping: "b.mtl4archive") == 1)
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(Set(left) == ["b.mtl4archive", "notes.txt"])
    }

    @Test func everyPartOfTheBuildChangesTheArchiveName() {
        let base = PipelineCacheFolder.archiveName(osBuild: "26A1", gpu: "M1", stamps: ["1", "2"])
        #expect(base.hasSuffix(".mtl4archive"))
        let changed = [
            PipelineCacheFolder.archiveName(osBuild: "26A2", gpu: "M1", stamps: ["1", "2"]),
            PipelineCacheFolder.archiveName(osBuild: "26A1", gpu: "M2", stamps: ["1", "2"]),
            PipelineCacheFolder.archiveName(osBuild: "26A1", gpu: "M1", stamps: ["1", "3"])
        ]
        #expect(!changed.contains(base))
        #expect(Set(changed).count == 3)
    }
}
