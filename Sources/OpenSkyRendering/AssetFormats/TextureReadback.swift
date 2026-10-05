// Decodes a texture of any sampled format to RGBA8 on the GPU. The GPU's own
// decoder is the reference, because it is what the renderer shows.

import Metal

/// One compute pass per call, waited on. For tools and tests, not for frames.
public final class TextureReadback {
    private let device: MTLDevice
    private let copyPipeline: MTLComputePipelineState
    private let scaledPipeline: MTLComputePipelineState
    private let queue: MTL4CommandQueue
    private let allocator: MTL4CommandAllocator
    private let commandBuffer: MTL4CommandBuffer
    private let argumentTable: MTL4ArgumentTable
    private let residency: MTLResidencySet
    private let event: MTLSharedEvent
    private var submitted: UInt64 = 0

    public init(device: MTLDevice, library: MTLLibrary) throws {
        self.device = device
        let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())
        copyPipeline = try Self.pipeline("textureReadbackCopy", library, compiler)
        scaledPipeline = try Self.pipeline("textureReadbackScaled", library, compiler)
        queue = try Renderer.makeCommandQueue(device: device)
        commandBuffer = try Renderer.makeCommandBuffer(device: device)
        guard let allocator = device.makeCommandAllocator() else {
            throw RendererError.commandAllocatorUnavailable
        }
        self.allocator = allocator
        let tableDescriptor = MTL4ArgumentTableDescriptor()
        tableDescriptor.maxTextureBindCount = 2
        argumentTable = try device.makeArgumentTable(descriptor: tableDescriptor)
        residency = try Renderer.makeResidencySet(device: device, allocations: [])
        guard let event = device.makeSharedEvent() else {
            throw RendererError.sharedEventUnavailable
        }
        self.event = event
    }

    /// The exact texels of one mip level.
    public func pixels(of texture: MTLTexture, level: Int) throws -> TexturePixels {
        guard
            let view = texture.makeTextureView(
                pixelFormat: texture.pixelFormat,
                textureType: .type2D,
                levels: level ..< level + 1,
                slices: 0 ..< 1
            )
        else { throw RendererError.textureAllocationFailed }
        return try run(
            copyPipeline,
            source: view,
            width: max(1, texture.width >> level),
            height: max(1, texture.height >> level)
        )
    }

    /// Level 0 resampled bilinearly to `width` by `height`.
    public func pixels(of texture: MTLTexture, width: Int, height: Int) throws -> TexturePixels {
        try run(scaledPipeline, source: texture, width: width, height: height)
    }

    private func run(
        _ pipeline: MTLComputePipelineState,
        source: MTLTexture,
        width: Int,
        height: Int
    ) throws -> TexturePixels {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = .shaderWrite
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.textureAllocationFailed
        }
        residency.addAllocations([source, target])
        residency.commit()
        defer {
            residency.removeAllAllocations()
            residency.commit()
        }
        try encode(pipeline, source: source, target: target)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(
            &rgba,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        return TexturePixels(width: width, height: height, rgba: rgba)
    }

    private func encode(
        _ pipeline: MTLComputePipelineState,
        source: MTLTexture,
        target: MTLTexture
    ) throws {
        allocator.reset()
        commandBuffer.beginCommandBuffer(allocator: allocator)
        commandBuffer.useResidencySet(residency)
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            commandBuffer.endCommandBuffer()
            throw RendererError.encoderUnavailable
        }
        argumentTable.setTexture(source.gpuResourceID, index: 0)
        argumentTable.setTexture(target.gpuResourceID, index: 1)
        encoder.setComputePipelineState(pipeline)
        encoder.setArgumentTable(argumentTable)
        encoder.dispatchThreads(
            threadsPerGrid: MTLSize(width: target.width, height: target.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.endCommandBuffer()
        submitted += 1
        queue.commit([commandBuffer])
        queue.signalEvent(event, value: submitted)
        guard event.wait(untilSignaledValue: submitted, timeoutMS: 10000) else {
            throw RendererError.gpuTimeout
        }
    }

    private static func pipeline(
        _ name: String,
        _ library: MTLLibrary,
        _ compiler: MTL4Compiler
    ) throws -> MTLComputePipelineState {
        let function = MTL4LibraryFunctionDescriptor()
        function.library = library
        function.name = name
        let descriptor = MTL4ComputePipelineDescriptor()
        descriptor.computeFunctionDescriptor = function
        return try compiler.makeComputePipelineState(descriptor: descriptor)
    }
}
