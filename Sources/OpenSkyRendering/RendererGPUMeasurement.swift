// Per-frame GPU time and GPU memory for the benchmarks. GPU time comes from the
// same commit feedback `FrameStats` reads; memory comes from the device and the
// renderer's residency set.

import Metal
import Synchronization

/// GPU time of each committed frame, in commit order. Commit feedback runs on a
/// Metal thread, so the log takes spans behind a lock.
nonisolated public final class GPUFrameLog: Sendable {
    private let spansMS = Mutex<[Double]>([])

    public init() {}

    /// Host times in seconds, as `MTL4CommitFeedback` reports them.
    public func record(start: CFTimeInterval, end: CFTimeInterval) {
        guard end > start else { return }
        spansMS.withLock { $0.append((end - start) * 1000) }
    }

    public func take() -> [Double] {
        spansMS.withLock { spans in
            defer { spans = [] }
            return spans
        }
    }
}

/// GPU memory at one moment, in bytes.
nonisolated public struct GPUMemoryUsage: Equatable, Sendable {
    /// `MTLDevice.currentAllocatedSize`: every allocation of the process.
    public var totalBytes = 0
    /// Resident textures that a pass renders into: color, depth, and shadow maps.
    public var renderTargetBytes = 0
    /// Resident textures that shaders only read.
    public var textureBytes = 0

    public init(totalBytes: Int = 0, renderTargetBytes: Int = 0, textureBytes: Int = 0) {
        self.totalBytes = totalBytes
        self.renderTargetBytes = renderTargetBytes
        self.textureBytes = textureBytes
    }

    /// The larger value of each field, so a peak can combine samples.
    public func fieldMaximum(_ other: Self) -> Self {
        Self(
            totalBytes: max(totalBytes, other.totalBytes),
            renderTargetBytes: max(renderTargetBytes, other.renderTargetBytes),
            textureBytes: max(textureBytes, other.textureBytes)
        )
    }
}

extension Renderer {
    /// Walks the residency set, so it costs one pass over every resident
    /// allocation. Call it outside a timed frame.
    public func gpuMemoryUsage() -> GPUMemoryUsage {
        var usage = GPUMemoryUsage(totalBytes: device.currentAllocatedSize)
        for allocation in residencySet.allAllocations {
            guard let texture = allocation as? MTLTexture else { continue }
            if texture.usage.contains(.renderTarget) {
                usage.renderTargetBytes += texture.allocatedSize
            } else {
                usage.textureBytes += texture.allocatedSize
            }
        }
        return usage
    }
}
