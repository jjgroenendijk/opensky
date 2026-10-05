// How a cache file is stored on disk, and the two ways to load it: a CPU read,
// or Metal fast resource loading (MTLIO), which reads and decompresses a file
// straight into a texture or buffer. A compressed file uses MTLIO's chunked
// format, so both paths read it through an MTLIO handle.

import Foundation
import Metal

nonisolated public enum AssetFileStorage: String, CaseIterable, Codable, Sendable {
    case raw
    case lz4
    case lzfse
    case lzBitmap
    case zlib

    var compression: MTLIOCompressionMethod? {
        switch self {
        case .raw: nil
        case .lz4: .lz4
        case .lzfse: .lzfse
        case .lzBitmap: .lzBitmap
        case .zlib: .zlib
        }
    }
}

nonisolated public enum AssetFileStorageError: Error, Equatable, Sendable {
    case compressionContextFailed(String)
    case compressionFailed(String)
    case ioFailed(String)
}

/// Writes cache files and loads them back. One MTLIO queue, waited on per load.
nonisolated public final class AssetFileLoader {
    private let device: MTLDevice
    private let queue: MTLIOCommandQueue

    public init(device: MTLDevice) throws {
        self.device = device
        queue = try device.makeIOCommandQueue(descriptor: MTLIOCommandQueueDescriptor())
    }

    public static func write(_ bytes: Data, to url: URL, storage: AssetFileStorage) throws {
        guard let method = storage.compression else {
            try bytes.write(to: url)
            return
        }
        guard
            let context = MTLIOCreateCompressionContext(
                url.path(percentEncoded: false), method,
                MTLIOCompressionContextDefaultChunkSize()
            )
        else { throw AssetFileStorageError.compressionContextFailed(url.lastPathComponent) }
        bytes.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                MTLIOCompressionContextAppendData(context, base, raw.count)
            }
        }
        guard MTLIOFlushAndDestroyCompressionContext(context) == .complete else {
            throw AssetFileStorageError.compressionFailed(url.lastPathComponent)
        }
    }

    /// The CPU path: the whole file, decompressed, in memory.
    public func read(_ url: URL, storage: AssetFileStorage, byteCount: Int) throws -> Data {
        guard storage.compression != nil else { return try Data(contentsOf: url) }
        var bytes = Data(count: byteCount)
        let handle = try handle(url, storage)
        let command = queue.makeCommandBuffer()
        bytes.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                command.loadBytes(
                    base,
                    size: byteCount,
                    sourceHandle: handle,
                    sourceHandleOffset: 0
                )
            }
        }
        try finish(command, url)
        return bytes
    }

    /// Streams every level of `payload`'s layout from the file into `texture`.
    public func load(
        _ url: URL,
        storage: AssetFileStorage,
        layout payload: GPUTexturePayload,
        into texture: MTLTexture
    ) throws {
        let handle = try handle(url, storage)
        let command = queue.makeCommandBuffer()
        for (index, level) in payload.levels.enumerated() {
            command.load(
                texture,
                slice: 0,
                level: index,
                size: MTLSize(width: level.width, height: level.height, depth: 1),
                sourceBytesPerRow: level.bytesPerRow,
                sourceBytesPerImage: level.length,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceHandle: handle,
                sourceHandleOffset: level.offset
            )
        }
        try finish(command, url)
    }

    /// Streams byte ranges of the file into buffers, one range per buffer.
    public func load(
        _ url: URL,
        storage: AssetFileStorage,
        ranges: [(buffer: MTLBuffer, fileOffset: Int)]
    ) throws {
        let handle = try handle(url, storage)
        let command = queue.makeCommandBuffer()
        for range in ranges {
            command.load(
                range.buffer, offset: 0, size: range.buffer.length,
                sourceHandle: handle, sourceHandleOffset: range.fileOffset
            )
        }
        try finish(command, url)
    }

    private func handle(_ url: URL, _ storage: AssetFileStorage) throws -> MTLIOFileHandle {
        if let method = storage.compression {
            return try device.makeIOFileHandle(url: url, compressionMethod: method)
        }
        return try device.makeIOFileHandle(url: url)
    }

    private func finish(_ command: MTLIOCommandBuffer, _ url: URL) throws {
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .complete else {
            throw AssetFileStorageError.ioFailed(
                "\(url.lastPathComponent): \(command.error.map(String.init(describing:)) ?? "")"
            )
        }
    }
}
