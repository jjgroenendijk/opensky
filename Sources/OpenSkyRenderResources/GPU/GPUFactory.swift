// Metal allocations that every GPU resource and the renderer share.

import Metal

nonisolated public enum GPUFactory {
    /// Every per-frame ring holds one slot per frame the GPU may still be drawing.
    public static let maxFramesInFlight = 3

    public static func makeCommandQueue(device: MTLDevice) throws -> MTL4CommandQueue {
        guard let queue = device.makeMTL4CommandQueue() else {
            throw RendererError.commandQueueUnavailable
        }
        return queue
    }

    public static func makeCommandBuffer(device: MTLDevice) throws -> MTL4CommandBuffer {
        guard let buffer = device.makeCommandBuffer() else {
            throw RendererError.commandBufferUnavailable
        }
        return buffer
    }

    public static func makeUniformBuffer(
        device: MTLDevice,
        length: Int,
        label: String
    ) throws -> MTLBuffer {
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared)
        else { throw RendererError.bufferAllocationFailed }
        buffer.label = label
        return buffer
    }

    public static func makeResidencySet(
        device: MTLDevice,
        allocations: [MTLAllocation]
    ) throws -> MTLResidencySet {
        let descriptor = MTLResidencySetDescriptor()
        descriptor.initialCapacity = allocations.count
        let residencySet = try device.makeResidencySet(descriptor: descriptor)
        residencySet.addAllocations(allocations)
        residencySet.commit()
        return residencySet
    }
}
