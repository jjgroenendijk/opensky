// Loads cached textures with Metal fast resource loading: one IO command buffer
// per batch reads the level bytes from the cache entry files straight into the
// textures, and `flush` waits for it. A batch is one cell build, so the cell
// is handed over only after its textures are complete. Scratch memory for the
// texture copies is freed per command, not pooled by the queue.
// See docs/engine/asset-cache.md, "Direct GPU loading".

import Foundation
import Metal
import OpenSkyAssetCache
import Synchronization

nonisolated public struct FastTextureLoadStats: Equatable, Sendable {
    public var batches = 0
    public var textures = 0
    public var bytes = 0
    /// Textures and mesh buffers that fell back to the CPU because the IO buffer failed.
    public var fallbacks = 0
    /// From the first load of the last batch to its completion.
    public var lastBatchMS = 0.0
    public var lastBatchTextures = 0
    public var lastBatchBytes = 0
    /// Cached meshes read into GPU buffers, and their bytes.
    public var meshes = 0
    public var meshBytes = 0
    public var lastBatchMeshes = 0
    /// Textures loaded on the CPU because their cache entry is on an external volume.
    public var externalSkips = 0

    public init() {}
}

/// The on/off switch and the counters, shared between the build queue and the panel.
nonisolated public final class FastTextureLoadControl: Sendable {
    private let enabled: Atomic<Bool>
    private let meshesEnabled: Atomic<Bool>
    private let externalEnabled: Atomic<Bool>
    private let stats = Mutex(FastTextureLoadStats())

    public init(isEnabled: Bool, loadsMeshes: Bool = false, readsExternalDisks: Bool = false) {
        enabled = Atomic(isEnabled)
        meshesEnabled = Atomic(loadsMeshes)
        externalEnabled = Atomic(readsExternalDisks)
    }

    /// External disks too. Off by default: there it saves no time and keeps scratch memory.
    public var readsExternalDisks: Bool {
        get { externalEnabled.load(ordering: .relaxed) }
        set { externalEnabled.store(newValue, ordering: .relaxed) }
    }

    public var isEnabled: Bool {
        get { enabled.load(ordering: .relaxed) }
        set { enabled.store(newValue, ordering: .relaxed) }
    }

    /// Cached meshes also load this way. Off by default: see docs/engine/asset-cache.md.
    public var loadsMeshes: Bool {
        get { meshesEnabled.load(ordering: .relaxed) }
        set { meshesEnabled.store(newValue, ordering: .relaxed) }
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

    /// A buffer the batch fills from a file range.
    private struct PendingBytes {
        let buffer: MTLBuffer
        let file: URL
        let offset: Int
    }

    public let control: FastTextureLoadControl
    private let device: MTLDevice
    private let queue: MTLIOCommandQueue
    private var buffer: MTLIOCommandBuffer?
    private var handles: [URL: MTLIOFileHandle] = [:]
    private var internalFolders: [URL: Bool] = [:]
    private var pending: [Pending] = []
    private var pendingMeshBytes: [PendingBytes] = []
    private var batchStart: ContinuousClock.Instant?

    public init(device: MTLDevice, control: FastTextureLoadControl) throws {
        self.device = device
        self.control = control
        let descriptor = MTLIOCommandQueueDescriptor()
        descriptor.type = .concurrent
        descriptor.scratchBufferAllocator = TransientScratchAllocator(device: device)
        queue = try device.makeIOCommandQueue(descriptor: descriptor)
    }

    /// The IO queue keeps the memory of each scratch buffer it used. From an
    /// external disk it saves no time, so it reads only from internal volumes.
    /// See docs/engine/asset-cache.md, "Direct GPU loading".
    public func reads(from file: URL) -> Bool {
        if control.readsExternalDisks {
            return true
        }
        let folder = file.deletingLastPathComponent()
        if let known = internalFolders[folder] {
            return known
        }
        let isInternal = (try? folder.resourceValues(forKeys: [.volumeIsInternalKey]))?
            .volumeIsInternal ?? false
        internalFolders[folder] = isInternal
        return isInternal
    }

    func recordExternalSkip() {
        control.record { $0.externalSkips += 1 }
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

    /// Queues the ready bytes of every mesh of `entry` into new buffers. The buffers hold
    /// no data until `flush` returns. `entry.value.isReady` must hold.
    public func enqueue(
        _ entry: AssetCacheEntryRead<ReadyModelLayout>, label: String
    ) throws -> [RenderMesh] {
        let handle = try handle(for: entry.file)
        let meshes = try entry.value.meshes.map { layout in
            guard layout.isReady, let bounds = layout.bounds else {
                throw RenderMeshError.emptyMesh
            }
            let name = layout.name ?? label
            return try RenderMesh(
                layout: layout, bounds: bounds,
                vertexBuffer: queueBuffer(
                    layout.vertexRange, of: entry, handle: handle, label: "\(name).vertices"
                ),
                indexBuffer: queueBuffer(
                    layout.indexRange, of: entry, handle: handle, label: "\(name).indices"
                )
            )
        }
        let bytes = entry.value.meshes.reduce(0) { $0 + $1.vertexRange.count + $1.indexRange.count }
        control.record { stats in
            stats.meshes += meshes.count
            stats.meshBytes += bytes
        }
        return meshes
    }

    private func queueBuffer(
        _ range: Range<Int>, of entry: AssetCacheEntryRead<ReadyModelLayout>,
        handle: MTLIOFileHandle, label: String
    ) throws -> MTLBuffer {
        guard let buffer = device.makeBuffer(length: range.count, options: .storageModeShared)
        else { throw RenderMeshError.bufferAllocationFailed }
        buffer.label = label
        let offset = entry.payloadOffset + range.lowerBound
        currentBuffer().load(
            buffer, offset: 0, size: range.count, sourceHandle: handle,
            sourceHandleOffset: offset
        )
        pendingMeshBytes.append(PendingBytes(buffer: buffer, file: entry.file, offset: offset))
        return buffer
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
            pendingMeshBytes.forEach(Self.fillFromFile)
            fallbacks = pending.count + pendingMeshBytes.count
        }
        let meshBuffers = pendingMeshBytes.count
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
            stats.lastBatchMeshes = meshBuffers / 2
        }
        self.buffer = nil
        batchStart = nil
        pending.removeAll()
        pendingMeshBytes.removeAll()
        handles.removeAll()
    }

    /// The CPU fallback for a failed batch. A short read leaves zeros, which draw nothing.
    private static func fillFromFile(_ item: PendingBytes) {
        guard let file = try? FileHandle(forReadingFrom: item.file) else { return }
        defer { try? file.close() }
        guard
            (try? file.seek(toOffset: UInt64(item.offset))) != nil,
            let bytes = try? file.read(upToCount: item.buffer.length)
        else { return }
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            item.buffer.contents().copyMemory(from: base, byteCount: raw.count)
        }
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

/// The queue's own allocator keeps its scratch buffers, up to 8 MiB each, for
/// the life of the queue. This one lets each buffer go when its command ends.
nonisolated final class TransientScratchAllocator: NSObject, MTLIOScratchBufferAllocator, Sendable {
    private let device: any MTLDevice

    init(device: any MTLDevice) {
        self.device = device
    }

    func makeScratchBuffer(minimumSize: Int) -> (any MTLIOScratchBuffer)? {
        device.makeBuffer(length: minimumSize, options: .storageModeShared)
            .map(TransientScratchBuffer.init)
    }
}

nonisolated final class TransientScratchBuffer: NSObject, MTLIOScratchBuffer {
    let buffer: any MTLBuffer

    init(buffer: any MTLBuffer) {
        self.buffer = buffer
    }
}

nonisolated extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}
