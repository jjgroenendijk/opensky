// Renderer support types, split from Renderer.swift to keep that file inside
// the 500-line limit when the audio subsystem fields landed (M9.1.3).

import Metal

/// GPU resources retired by a scene swap, still possibly referenced by
/// frames in flight when they were retired. The strong references here keep
/// the allocations alive; residency-set removal waits until
/// `endFrameEvent.signaledValue` proves `lastFrameIndex` drained.
nonisolated struct RetiredAllocations {
    /// Highest frame index that may still reference these allocations.
    let lastFrameIndex: UInt64
    let allocations: [MTLAllocation]
}

nonisolated enum RendererError: Error {
    case deviceUnavailable
    case commandQueueUnavailable
    case commandBufferUnavailable
    case commandAllocatorUnavailable
    case sharedEventUnavailable
    case bufferAllocationFailed
    case defaultLibraryMissing
    case pipelineAttachmentMissing
    case depthStateAllocationFailed
    case samplerAllocationFailed
    case textureAllocationFailed
    case encoderUnavailable
    case gpuTimeout
    case offscreenPumpTimedOut(maxFrames: Int)
}
