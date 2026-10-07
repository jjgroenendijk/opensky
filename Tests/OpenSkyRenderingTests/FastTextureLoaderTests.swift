// Fast resource loading: a cached texture read by an IO command buffer holds
// the same texels as the CPU upload of the same entry.

import EngineTesting
import Foundation
import Metal
import OpenSkyAssetCache
import OpenSkyGameData
@testable import OpenSkyRendering
import TagsTesting
import Testing

@MainActor
@Suite(.tags(.gpu))
struct FastTextureLoaderTests {
    /// The readback runs on a Metal 4 queue, which the CI runner's virtual GPU lacks.
    nonisolated private static let device: MTLDevice? = {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            return nil
        }
        return device
    }()

    nonisolated private static var hasDevice: Bool {
        device != nil
    }

    private struct OneFile: GameFileSource {
        let path = "textures\\rock.dds"

        func exists(_ path: String) -> Bool {
            provenance(forPath: path) != nil
        }

        func contents(forPath path: String) throws -> Data {
            throw VFSError.fileNotFound(path: path)
        }

        func archiveEntries() -> [VFSEntry] {
            []
        }

        func fileNames(inDirectory _: String) -> [String] {
            []
        }

        func provenance(forPath path: String) -> GameFileProvenance? {
            (try? VirtualFileSystem.normalize(path)) == self.path
                ? GameFileProvenance(origin: "a.bsa", size: 10, modified: 5) : nil
        }
    }

    /// Three levels, so the level offsets inside the entry file are exercised.
    private func texture() -> ReadyTexture {
        let sizes = [8 * 8, 4 * 4, 2 * 2]
        let bytes = Data(sizes.flatMap { count in
            (0 ..< count * 4).map { UInt8(($0 * 7) & 0xFF) }
        })
        return ReadyTexture(format: .rgba8, width: 8, height: 8, mipCount: 3, bytes: bytes)
    }

    private func cachedEntry() throws -> AssetCacheEntryRead<ReadyTexture> {
        let root = FileManager.default.temporaryDirectory
            .appending(
                path: "FastTextureLoaderTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let files = OneFile()
        let reader = try AssetCacheReader(
            store: AssetCacheStore(root: root, limitBytes: 1 << 30), files: files, preset: .balanced
        )
        let source = try #require(reader.stamp(forPath: files.path))
        try reader.store.store(ReadyTextureCodec.encode(texture()), for: AssetCacheRequest(
            kind: .texture, source: source,
            converterVersion: AssetConverterVersion.texture, preset: .balanced
        ))
        return try #require(reader.entry(forPath: files.path, decoder: .readyTexture))
    }

    @Test(.enabled(if: Self.hasDevice)) func aFlushedBatchMatchesTheCPUUpload() throws {
        let device = try #require(Self.device)
        let library = try ShaderLibraryFixture.library(device: device)
        let readback = try TextureReadback(device: device, library: library)
        let control = FastTextureLoadControl(isEnabled: true)
        let loader = try FastTextureLoader(device: device, control: control)
        let entry = try cachedEntry()
        let fast = try loader.enqueue(entry, usage: .color, label: "fast")
        loader.flush()
        let direct = try TextureLoader(device: device)
            .upload(ready: entry.value, usage: .color, label: "direct")
        for level in 0 ..< 3 {
            #expect(try readback.pixels(of: fast, level: level)
                == readback.pixels(of: direct, level: level))
        }
        let stats = control.snapshot
        #expect(stats.batches == 1)
        #expect(stats.textures == 1)
        #expect(stats.bytes == entry.value.expectedByteCount)
        #expect(stats.fallbacks == 0)
    }

    @Test(.enabled(if: Self.hasDevice)) func aFlushWithNothingQueuedRecordsNoBatch() throws {
        let device = try #require(Self.device)
        let control = FastTextureLoadControl(isEnabled: true)
        try FastTextureLoader(device: device, control: control).flush()
        #expect(control.snapshot.batches == 0)
    }

    @Test(.enabled(if: Self.hasDevice)) func eachScratchRequestGetsItsOwnBuffer() throws {
        let device = try #require(Self.device)
        let allocator = TransientScratchAllocator(device: device)
        let first = try #require(allocator.makeScratchBuffer(minimumSize: 64 << 10))
        let second = try #require(allocator.makeScratchBuffer(minimumSize: 64 << 10))
        #expect(first.buffer.length >= 64 << 10)
        #expect(first.buffer !== second.buffer)
    }
}
