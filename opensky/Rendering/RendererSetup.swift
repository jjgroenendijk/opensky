// Renderer setup factories: pipelines, depth state, sampler, uniform
// buffers, residency set. Static + self-contained (device passed in) so they
// live apart from the render loop (file-length limits, docs/rendering/
// metal4-renderer.md). Split from Renderer.swift, todo 2.6.

import Metal
import MetalKit
import simd

// MARK: - Setup factories

extension Renderer {
    static func makeUniformBuffer(
        device: MTLDevice,
        length: Int,
        label: String
    ) throws -> MTLBuffer {
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared)
        else { throw RendererError.bufferAllocationFailed }
        buffer.label = label
        return buffer
    }

    static func makePipelines(
        device: MTLDevice,
        view: MTKView
    ) throws -> (opaque: MTLRenderPipelineState, alphaTest: MTLRenderPipelineState) {
        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.defaultLibraryMissing
        }
        let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())

        func makeVariant(alphaTest: Bool) throws -> MTLRenderPipelineState {
            let vertexFunction = MTL4LibraryFunctionDescriptor()
            vertexFunction.library = library
            vertexFunction.name = "staticMeshVertex"

            let fragmentFunction = MTL4LibraryFunctionDescriptor()
            fragmentFunction.library = library
            fragmentFunction.name = "staticMeshFragment"
            let specialized = MTL4SpecializedFunctionDescriptor()
            specialized.functionDescriptor = fragmentFunction
            let constants = MTLFunctionConstantValues()
            var enabled = alphaTest
            constants.setConstantValue(
                &enabled,
                type: .bool,
                index: FunctionConstantIndex.alphaTest.rawValue
            )
            specialized.constantValues = constants

            let descriptor = MTL4RenderPipelineDescriptor()
            descriptor.label = alphaTest ? "StaticMeshAlphaTest" : "StaticMeshOpaque"
            descriptor.rasterSampleCount = view.sampleCount
            descriptor.vertexFunctionDescriptor = vertexFunction
            descriptor.fragmentFunctionDescriptor = specialized
            descriptor.vertexDescriptor = StaticVertexLayout.vertexDescriptor()
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            return try compiler.makeRenderPipelineState(descriptor: descriptor)
        }

        return try (opaque: makeVariant(alphaTest: false), alphaTest: makeVariant(alphaTest: true))
    }

    /// Standard opaque depth: write-through, closer fragment wins. Metal 4
    /// binds the depth attachment format at pass time (MTKView
    /// `depth32Float`), not in the pipeline descriptor.
    static func makeDepthState(device: MTLDevice) throws -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.label = "OpaqueDepth"
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true
        guard let state = device.makeDepthStencilState(descriptor: descriptor) else {
            throw RendererError.depthStateAllocationFailed
        }
        return state
    }

    /// Mipmapped trilinear + anisotropic sampler, repeat addressing (world
    /// textures tile). Argument-table binding needs the GPU resource ID.
    static func makeSampler(device: MTLDevice) throws -> MTLSamplerState {
        let descriptor = MTLSamplerDescriptor()
        descriptor.label = "TrilinearAniso"
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.maxAnisotropy = 8
        descriptor.sAddressMode = .repeat
        descriptor.tAddressMode = .repeat
        descriptor.supportArgumentBuffers = true
        guard let sampler = device.makeSamplerState(descriptor: descriptor) else {
            throw RendererError.samplerAllocationFailed
        }
        return sampler
    }

    static func makeResidencySet(
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
