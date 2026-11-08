// Metal allocations that every GPU resource and the renderer share.

public import Metal

nonisolated public enum GPUFactory {
    /// Every per-frame ring holds one slot per frame the GPU may still be drawing.
    public static let maxFramesInFlight = 3

    public static func makeCommandQueue(device: any MTLDevice) throws -> any MTL4CommandQueue {
        guard let queue = device.makeMTL4CommandQueue() else {
            throw RendererError.commandQueueUnavailable
        }
        return queue
    }

    public static func makeCommandBuffer(device: any MTLDevice) throws -> any MTL4CommandBuffer {
        guard let buffer = device.makeCommandBuffer() else {
            throw RendererError.commandBufferUnavailable
        }
        return buffer
    }

    public static func makeUniformBuffer(
        device: any MTLDevice,
        length: Int,
        label: String
    ) throws -> any MTLBuffer {
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared)
        else { throw RendererError.bufferAllocationFailed }
        buffer.label = label
        return buffer
    }

    public static func makeResidencySet(
        device: any MTLDevice,
        allocations: [any MTLAllocation]
    ) throws -> any MTLResidencySet {
        let descriptor = MTLResidencySetDescriptor()
        descriptor.initialCapacity = allocations.count
        let residencySet = try device.makeResidencySet(descriptor: descriptor)
        residencySet.addAllocations(allocations)
        residencySet.commit()
        return residencySet
    }
}
