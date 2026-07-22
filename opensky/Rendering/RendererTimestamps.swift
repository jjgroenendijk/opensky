// MTKView configuration + GPU counter-heap timestamp reads, split from
// Renderer.swift (file-length limits). These touch only the renderer's
// internal members (no private(set) setters), so they live cleanly in their
// own file next to the draw loop that consumes the timestamps.

import Metal
import MetalKit

extension Renderer {
    static func configure(view: MTKView) {
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = 1
    }

    /// Two timestamp entries (frame start/end) per in-flight slot; nil when the
    /// device cannot allocate one — stats then report CPU time only.
    static func makeTimestampHeap(device: MTLDevice) -> MTL4CounterHeap? {
        let heapDescriptor = MTL4CounterHeapDescriptor()
        heapDescriptor.type = .timestamp
        heapDescriptor.count = 2 * maxFramesInFlight
        return try? device.makeCounterHeap(descriptor: heapDescriptor)
    }

    /// Reads a slot's timestamp pair straight from the counter heap. Only
    /// valid when the caller proved (shared-event wait) that the frame which
    /// wrote the slot finished.
    func readTimestampPair(slot: Int) -> (start: UInt64, end: UInt64)? {
        guard
            let heap = timestampHeap,
            let data = try? heap.resolveCounterRange(slot * 2 ..< slot * 2 + 2),
            data.count >= 2 * MemoryLayout<MTL4TimestampHeapEntry>.stride
        else { return nil }
        let entries = data.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: MTL4TimestampHeapEntry.self))
        }
        return (entries[0].timestamp, entries[1].timestamp)
    }

    /// Resolves the timestamp pair the slot's previous frame wrote; safe
    /// because the shared-event wait guarantees that frame finished. The
    /// depth guard skips the first ring lap, before any slot was written.
    func resolveTimestamps(slot: Int) -> (start: UInt64, end: UInt64)? {
        guard frameIndex >= 2 * Self.maxFramesInFlight else { return nil }
        return readTimestampPair(slot: slot)
    }
}
