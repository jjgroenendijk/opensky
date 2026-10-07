// Renderer support types, kept apart to hold Renderer.swift under the file limit.

import Metal

/// GPU resources retired by a scene swap, still possibly referenced by
/// frames in flight when they were retired. The strong references here keep
/// the allocations alive; residency-set removal waits until
/// `endFrameEvent.signaledValue` proves `lastFrameIndex` drained.
nonisolated public struct RetiredAllocations {
    /// Highest frame index that may still reference these allocations.
    public let lastFrameIndex: UInt64
    public let allocations: [MTLAllocation]
}

nonisolated public enum RendererError: Error {
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
    /// MetalFX could not make a temporal scaler or its targets for these sizes.
    case upscalerUnavailable
}
