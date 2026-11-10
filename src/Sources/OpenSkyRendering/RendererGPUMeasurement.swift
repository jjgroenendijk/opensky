// Per-frame GPU time and GPU memory for the benchmarks. GPU time comes from the
// same commit feedback `FrameStats` reads; memory comes from the device and the
// renderer's residency set.

import Metal
import Synchronization

/// What the GPU reported since the last take: the busy time of each finished frame,
/// and the frames that left no time.
nonisolated public struct GPUFrameReport: Equatable, Sendable {
    public var spansMS: [Double] = []
    /// Command buffers whose commit feedback carried an error. They report no time.
    public var failedCommits = 0
    public var lastFailure: String?
    /// Frames not encoded because the GPU still used their slot.
    public var skippedFrames = 0

    public init(
        spansMS: [Double] = [], failedCommits: Int = 0, lastFailure: String? = nil,
        skippedFrames: Int = 0
    ) {
        self.spansMS = spansMS
        self.failedCommits = failedCommits
        self.lastFailure = lastFailure
        self.skippedFrames = skippedFrames
    }
}

/// GPU time of each committed frame, in commit order. Commit feedback runs on a
/// Metal thread, so the log keeps its report behind a lock.
nonisolated public final class GPUFrameLog: Sendable {
    private let report = Mutex(GPUFrameReport())

    public init() {}

    /// Host times in seconds, as `MTL4CommitFeedback` reports them.
    func record(start: CFTimeInterval, end: CFTimeInterval) {
        guard end > start else { return }
        report.withLock { $0.spansMS.append((end - start) * 1000) }
    }

    func recordFailure(_ error: any Error) {
        let text = String(describing: error)
        report.withLock { report in
            report.failedCommits += 1
            report.lastFailure = text
        }
    }

    func recordSkippedFrame() {
        report.withLock { $0.skippedFrames += 1 }
    }

    public func take() -> GPUFrameReport {
        report.withLock { report in
            defer { report = GPUFrameReport() }
            return report
        }
    }
}

/// GPU memory at one moment, in bytes.
nonisolated public struct GPUMemoryUsage: Equatable, Sendable {
    /// `MTLDevice.currentAllocatedSize`: every allocation of the process.
    public var totalBytes = 0
    /// Resident textures that a pass renders into: color, depth, and shadow maps.
    public var renderTargetBytes = 0
    /// Resident textures that shaders only read, and the streamed textures' heaps.
    public var textureBytes = 0
    /// Resident buffers: meshes, rings, and staging.
    public var bufferBytes = 0
    /// Allocations in the residency set. A count that only grows means nothing leaves it.
    public var residentCount = 0
    /// The app's physical footprint: CPU memory plus the GPU allocations it maps.
    public var processBytes = 0
    /// The streamed textures' heap pool, part of `textureBytes`, and the tiles mapped in it.
    public var streamedReservedBytes = 0
    public var streamedUsedBytes = 0
    public var streamedTextures = 0
    /// Entries in the cell builder's texture and model caches, which eviction should shrink.
    public var cachedTextures = 0
    public var cachedModels = 0

    public init(totalBytes: Int = 0, renderTargetBytes: Int = 0, textureBytes: Int = 0) {
        self.totalBytes = totalBytes
        self.renderTargetBytes = renderTargetBytes
        self.textureBytes = textureBytes
    }

    /// The larger value of each field, so a peak can combine samples.
    public func fieldMaximum(_ other: Self) -> Self {
        var peak = self
        let fields: [WritableKeyPath<Self, Int>] = [
            \.totalBytes, \.renderTargetBytes, \.textureBytes, \.bufferBytes, \.residentCount,
            \.processBytes, \.streamedReservedBytes, \.streamedUsedBytes, \.streamedTextures,
            \.cachedTextures, \.cachedModels
        ]
        for field in fields {
            peak[keyPath: field] = max(self[keyPath: field], other[keyPath: field])
        }
        return peak
    }
}

extension Renderer {
    /// Walks the residency set, so it costs one pass over every resident
    /// allocation. Call it outside a timed frame.
    public func gpuMemoryUsage() -> GPUMemoryUsage {
        let resident = residencySet.allAllocations
        var usage = GPUMemoryUsage(totalBytes: device.currentAllocatedSize)
        usage.residentCount = resident.count
        let streaming = textureStreaming.stats
        usage.streamedReservedBytes = streaming.reservedBytes
        usage.streamedUsedBytes = streaming.usedBytes
        usage.streamedTextures = streaming.streamedTextures
        for allocation in resident {
            // Streamed textures keep their levels in placement heaps.
            if let heap = allocation as? (any MTLHeap), heap.type == .placement {
                usage.textureBytes += heap.size
                continue
            }
            if let buffer = allocation as? (any MTLBuffer) {
                usage.bufferBytes += buffer.allocatedSize
                continue
            }
            guard let texture = allocation as? (any MTLTexture) else { continue }
            if texture.usage.contains(.renderTarget) {
                usage.renderTargetBytes += texture.allocatedSize
            } else {
                usage.textureBytes += texture.allocatedSize
            }
        }
        return usage
    }
}
