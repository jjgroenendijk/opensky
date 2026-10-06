// Loads cached textures with Metal fast resource loading: one IO command buffer
// per batch reads the level bytes from the cache entry files straight into the
// textures, and `flush` waits for it. A batch is one cell build, so the cell
// is handed over only after its textures are complete.
// See docs/engine/asset-cache.md, "Fast resource loading".

import Foundation
import Metal
import OpenSkyAssetCache
import Synchronization

nonisolated public struct FastTextureLoadStats: Equatable, Sendable {
    public var batches = 0
    public var textures = 0
    public var bytes = 0
    /// Textures that fell back to the CPU upload because the IO buffer failed.
    public var fallbacks = 0
    /// From the first load of the last batch to its completion.
    public var lastBatchMS = 0.0
    public var lastBatchTextures = 0
    public var lastBatchBytes = 0

    public init() {}
}

/// The on/off switch and the counters, shared between the build queue and the panel.
nonisolated public final class FastTextureLoadControl: Sendable {
    private let enabled: Atomic<Bool>
    private let stats = Mutex(FastTextureLoadStats())

    public init(isEnabled: Bool) {
        enabled = Atomic(isEnabled)
    }

    public var isEnabled: Bool {
        get { enabled.load(ordering: .relaxed) }
        set { enabled.store(newValue, ordering: .relaxed) }
    }

    public var snapshot: FastTextureLoadStats {
        stats.withLock { $0 }
    }

    func record(_ change: (inout FastTextureLoadStats) -> Void) {
        stats.withLock { change(&$0) }
    }
}

/// Confined to the one cell-build queue, like `TextureLibrary`.
nonisolated public final class FastTextureLoader {
    private struct Pending {
        let texture: MTLTexture
        let ready: ReadyTexture
    }

    public let control: FastTextureLoadControl
    private let device: MTLDevice
    private let queue: MTLIOCommandQueue
    private var buffer: MTLIOCommandBuffer?
    private var handles: [URL: MTLIOFileHandle] = [:]
    private var pending: [Pending] = []
    private var batchStart: ContinuousClock.Instant?

    public init(device: MTLDevice, control: FastTextureLoadControl) throws {
        self.device = device
        self.control = control
        let descriptor = MTLIOCommandQueueDescriptor()
        descriptor.type = .concurrent
        queue = try device.makeIOCommandQueue(descriptor: descriptor)
    }

    /// Queues the levels of `entry` into a new texture. The texture holds no
    /// data until `flush` returns.
    public func enqueue(
        _ entry: AssetCacheEntryRead<ReadyTexture>, usage: TextureUsage, label: String
    ) throws -> MTLTexture {
        let ready = entry.value
        let texture = try TextureLoader.makeTexture(
            device: device,
            ready: ready,
            usage: usage,
            label: label
        )
        let handle = try handle(for: entry.file)
        let buffer = currentBuffer()
        let levelsOffset = entry.payloadOffset + ReadyTextureCodec.headerSize
        for level in 0 ..< ready.mipCount {
            let range = ready.levelRange(level)
            buffer.load(
                texture, slice: 0, level: level,
                size: MTLSize(
                    width: ready.width(level: level),
                    height: ready.height(level: level),
                    depth: 1
                ),
                sourceBytesPerRow: ready.bytesPerRow(level: level),
                sourceBytesPerImage: range.count,
                destinationOrigin: MTLOrigin(), sourceHandle: handle,
                sourceHandleOffset: levelsOffset + range.lowerBound
            )
        }
        pending.append(Pending(texture: texture, ready: ready))
        return texture
    }

    /// Commits the batch and waits for it. On an IO failure every texture of
    /// the batch is uploaded on the CPU from the mapped entry instead.
    public func flush() {
        guard let buffer, let start = batchStart else { return }
        buffer.commit()
        buffer.waitUntilCompleted()
        var fallbacks = 0
        if buffer.status != .complete {
            for item in pending {
                TextureLoader.replaceLevels(of: item.texture, with: item.ready)
            }
            fallbacks = pending.count
        }
        let bytes = pending.reduce(0) { $0 + $1.ready.expectedByteCount }
        let milliseconds = (ContinuousClock.now - start).milliseconds
        let count = pending.count
        control.record { stats in
            stats.batches += 1
            stats.textures += count
            stats.bytes += bytes
            stats.fallbacks += fallbacks
            stats.lastBatchMS = milliseconds
            stats.lastBatchTextures = count
            stats.lastBatchBytes = bytes
        }
        self.buffer = nil
        batchStart = nil
        pending.removeAll()
        handles.removeAll()
    }

    private func currentBuffer() -> MTLIOCommandBuffer {
        if let buffer {
            return buffer
        }
        let buffer = queue.makeCommandBuffer()
        self.buffer = buffer
        batchStart = .now
        return buffer
    }

    private func handle(for file: URL) throws -> MTLIOFileHandle {
        if let handle = handles[file] {
            return handle
        }
        let handle = try device.makeIOFileHandle(url: file)
        handles[file] = handle
        return handle
    }
}

nonisolated extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}
