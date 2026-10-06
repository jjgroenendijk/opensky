// Loads one batch of textures, such as the benchmark block's, four ways and
// times each: the archive path, the cache read on the CPU, and Metal fast
// resource loading (an IO command queue) from the raw cache entries and from
// LZ4 copies of them. See docs/engine/asset-cache.md, "Fast resource loading".

import Darwin
import Foundation
import Metal
import OpenSkyAssetCache
import OpenSkyFormatsMesh
import OpenSkyGameData

nonisolated public enum TextureBatchLoadMethod: String, CaseIterable, Sendable {
    case archive
    case cacheCPU
    case fastLoadRaw
    case fastLoadLZ4
}

nonisolated public struct TextureBatchLoadTiming: Equatable, Sendable {
    public let method: TextureBatchLoadMethod
    public let textures: Int
    public let bytes: Int
    public let wallMS: Double
    /// Process CPU time on every thread, so work moved off the CPU shows here.
    public let cpuMS: Double
}

/// One texture of the batch, read from its cache entry.
nonisolated struct TextureBatchItem {
    let path: String
    let entry: URL
    /// Where the level bytes start in the entry file.
    let levelsOffset: Int
    let texture: ReadyTexture
}

public final class TextureBatchLoadBenchmark {
    private let device: MTLDevice
    private let files: any GameFileSource
    private let items: [TextureBatchItem]
    private let loader: TextureLoader
    private let queue: MTLIOCommandQueue
    /// LZ4 copies of the entries, written once by `prepareCompressedCopies`.
    private var compressed: [URL] = []

    /// Uses the textures of `paths` that have a current entry in `reader`'s cache.
    public init(
        device: MTLDevice,
        files: any GameFileSource,
        reader: AssetCacheReader,
        paths: [String]
    ) throws {
        self.device = device
        self.files = files
        loader = try TextureLoader(device: device)
        let descriptor = MTLIOCommandQueueDescriptor()
        descriptor.type = .concurrent
        queue = try device.makeIOCommandQueue(descriptor: descriptor)
        items = paths.compactMap { Self.item(path: $0, reader: reader) }
    }

    public var textureCount: Int {
        items.count
    }

    public var entryURLs: [URL] {
        items.map(\.entry)
    }

    /// Writes an LZ4 copy of every entry into `folder`; MTLIO cannot read compressed bytes
    /// otherwise.
    public func prepareCompressedCopies(in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        compressed = try items.enumerated().map { index, item in
            let url = folder.appending(path: "\(index).lz4")
            let data = try Data(contentsOf: item.entry)
            guard
                let context = MTLIOCreateCompressionContext(
                    url.path(percentEncoded: false), .lz4, MTLIOCompressionContextDefaultChunkSize()
                ) else { throw TextureBatchLoadError.compressionFailed(url) }
            data.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    MTLIOCompressionContextAppendData(context, base, raw.count)
                }
            }
            guard MTLIOFlushAndDestroyCompressionContext(context) == .complete else {
                throw TextureBatchLoadError.compressionFailed(url)
            }
            return url
        }
    }

    public var compressedURLs: [URL] {
        compressed
    }

    public func run(_ method: TextureBatchLoadMethod) throws -> TextureBatchLoadTiming {
        let clock = ContinuousClock()
        let cpuStart = Self.processCPUSeconds()
        let start = clock.now
        let bytes: Int = switch method {
        case .archive: try loadFromArchive()
        case .cacheCPU: try loadFromCacheOnCPU()
        case .fastLoadRaw: try loadWithFastResourceLoading(
                sources: items.map(\.entry),
                compressed: false
            )
        case .fastLoadLZ4: try loadWithFastResourceLoading(sources: compressed, compressed: true)
        }
        let wall = clock.now - start
        return TextureBatchLoadTiming(
            method: method, textures: items.count, bytes: bytes,
            wallMS: Double(wall.components.attoseconds) / 1e15 + Double(wall.components.seconds) *
                1000,
            cpuMS: (Self.processCPUSeconds() - cpuStart) * 1000
        )
    }

    private func loadFromArchive() throws -> Int {
        var bytes = 0
        for item in items {
            let data = try files.contents(forPath: item.path)
            _ = try loader.upload(dds: DDSFile(data: data), usage: .color, label: item.path)
            bytes += data.count
        }
        return bytes
    }

    private func loadFromCacheOnCPU() throws -> Int {
        var bytes = 0
        for item in items {
            let file = try Data(contentsOf: item.entry, options: .mappedIfSafe)
            let (_, range) = try AssetCacheEntryCodec.decode(file)
            let ready = try ReadyTextureCodec.decode(file[range])
            _ = try loader.upload(ready: ready, usage: .color, label: item.path)
            bytes += file.count
        }
        return bytes
    }

    /// One IO command buffer for the whole batch, as a cell load would queue it.
    private func loadWithFastResourceLoading(sources: [URL], compressed: Bool) throws -> Int {
        guard sources.count == items.count
        else { throw TextureBatchLoadError.missingCompressedCopies }
        let buffer = queue.makeCommandBuffer()
        var bytes = 0
        for (item, source) in zip(items, sources) {
            let handle = try compressed
                ? device.makeIOFileHandle(url: source, compressionMethod: .lz4)
                : device.makeIOFileHandle(url: source)
            let texture = try privateTexture(for: item.texture)
            for level in 0 ..< item.texture.mipCount {
                let range = item.texture.levelRange(level)
                buffer.load(
                    texture, slice: 0, level: level,
                    size: MTLSize(
                        width: item.texture.width(level: level),
                        height: item.texture.height(level: level),
                        depth: 1
                    ),
                    sourceBytesPerRow: item.texture.bytesPerRow(level: level),
                    sourceBytesPerImage: range.count,
                    destinationOrigin: MTLOrigin(), sourceHandle: handle,
                    sourceHandleOffset: item.levelsOffset + range.lowerBound
                )
            }
            bytes += item.texture.expectedByteCount
        }
        buffer.commit()
        buffer.waitUntilCompleted()
        guard buffer.status == .complete
        else { throw TextureBatchLoadError.ioFailed(String(describing: buffer.error)) }
        return bytes
    }

    private func privateTexture(for ready: ReadyTexture) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = TextureLoader.pixelFormat(for: ready.format, usage: .color)
        descriptor.width = ready.width
        descriptor.height = ready.height
        descriptor.mipmapLevelCount = ready.mipCount
        descriptor.usage = .shaderRead
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw TextureLoaderError.textureAllocationFailed
        }
        return texture
    }

    nonisolated private static func item(
        path: String,
        reader: AssetCacheReader
    ) -> TextureBatchItem? {
        guard
            let source = reader.stamp(forPath: path),
            source.path.hasSuffix(".dds") else { return nil }
        let request = AssetCacheRequest(
            kind: .texture, source: source, converterVersion: AssetConverterVersion.texture,
            preset: reader.preset
        )
        guard
            case let .hit(hit) = reader.store.lookup(request, touching: false),
            !hit.payload.isEmpty,
            let texture = try? ReadyTextureCodec.decode(hit.payload)
        else { return nil }
        return TextureBatchItem(
            path: source.path, entry: reader.store.entryURL(kind: .texture, source: source),
            levelsOffset: hit.payloadRange.lowerBound + ReadyTextureCodec.headerSize,
            texture: texture
        )
    }

    nonisolated private static func processCPUSeconds() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
    }
}

nonisolated public enum TextureBatchLoadError: Error, Equatable {
    case compressionFailed(URL)
    case missingCompressedCopies
    case ioFailed(String)
}
