// Renderer setup factories: pipelines, depth state, sampler, uniform
// buffers, residency set. Static + self-contained (device passed in) so they
// live apart from the render loop (file-length limits, docs/rendering/
// metal4-renderer.md). Split from Renderer.swift, todo 2.6.

import Metal
import MetalKit
import simd

// MARK: - Setup factories

/// The scene pass's pipeline states, built together from one library.
nonisolated struct RenderPipelines {
    let sky: MTLRenderPipelineState
    let opaque: MTLRenderPipelineState
    let alphaTest: MTLRenderPipelineState
    let skinnedOpaque: MTLRenderPipelineState
    let skinnedAlphaTest: MTLRenderPipelineState
    let morphedSkinnedOpaque: MTLRenderPipelineState
    let morphedSkinnedAlphaTest: MTLRenderPipelineState
    let grass: MTLRenderPipelineState
    let terrain: MTLRenderPipelineState
    let water: MTLRenderPipelineState
    let particles: ParticlePipelines
    /// Render-debug twins of the five geometry paths (issue #144). Built
    /// alongside the shipping set so a mode change binds a state rather than
    /// compiling one mid-session.
    let debug: DebugRenderPipelines
}

nonisolated struct ParticlePipelines {
    let alpha: MTLRenderPipelineState
    let additive: MTLRenderPipelineState
    let additiveOne: MTLRenderPipelineState
    let multiply: MTLRenderPipelineState

    func pipeline(for mode: ParticleBlendMode) -> MTLRenderPipelineState {
        switch mode {
        case .alpha: alpha
        case .additive: additive
        case .additiveOne: additiveOne
        case .multiply: multiply
        }
    }
}

/// Sun-shadow depth pre-pass pipelines (M7.1.1): depth-only, no color
/// attachment. `alphaTest` carries a discard fragment; the rest run
/// depth-only. `skinned` handles both opaque and alpha-tested skinned casters
/// (skinned cutouts cast a conservative solid shadow in 7.1.1).
nonisolated struct ShadowPipelines {
    let staticCaster: MTLRenderPipelineState
    let alphaTest: MTLRenderPipelineState
    let skinned: MTLRenderPipelineState
    let morphedSkinned: MTLRenderPipelineState
    let terrain: MTLRenderPipelineState
}

/// Every long-lived sun-shadow GPU object, built + stored as a unit so the
/// renderer init/state stays compact.
nonisolated struct ShadowResources {
    let pipelines: ShadowPipelines
    let sampler: MTLSamplerState
    let map: MTLTexture
}

extension Renderer {
    static func makeCommandQueue(device: MTLDevice) throws -> MTL4CommandQueue {
        guard let queue = device.makeMTL4CommandQueue() else {
            throw RendererError.commandQueueUnavailable
        }
        return queue
    }

    static func makeCommandBuffer(device: MTLDevice) throws -> MTL4CommandBuffer {
        guard let buffer = device.makeCommandBuffer() else {
            throw RendererError.commandBufferUnavailable
        }
        return buffer
    }

    nonisolated static var nearPlane: Float {
        10
    }

    nonisolated static var farPlane: Float {
        65536
    }

    /// Sun-shadow far bound (high quality): 3 exterior cells (4096 units each),
    /// matching the resident streaming grid. Casters beyond it are un-shadowed
    /// by design.
    nonisolated static var shadowDistance: Float {
        12288
    }

    /// Low-quality sun-shadow far bound: 2 exterior cells. Shorter range +
    /// fewer cascades (see shadowCascadeCount) trade shadow reach for cost.
    nonisolated static var shadowDistanceLow: Float {
        8192
    }

    /// Light near plane extended backwards (toward the sun) by this many world
    /// units so casters between the sun and a cascade slice still render.
    nonisolated static var shadowCasterBackup: Float {
        12288
    }

    /// Blend between uniform + logarithmic cascade splits (0 = uniform).
    nonisolated static var shadowSplitLambda: Float {
        0.7
    }

    /// Raster depth bias for the shadow pre-pass: constant + slope-scaled,
    /// no clamp. Trades a little peter-panning for acne removal; tune against
    /// the real install if either shows.
    nonisolated static var shadowDepthBias: Float {
        2
    }

    nonisolated static var shadowSlopeScale: Float {
        3
    }

    static func makeCommandAllocators(device: MTLDevice) throws -> [MTL4CommandAllocator] {
        try (0 ..< maxFramesInFlight).map { _ in
            guard let allocator = device.makeCommandAllocator() else {
                throw RendererError.commandAllocatorUnavailable
            }
            return allocator
        }
    }

    /// Long-lived resources for passes outside the base scene pipelines.
    /// Grouping their factories keeps Renderer.init below the strict body cap.
    static func makeAuxiliaryResources(
        device: MTLDevice,
        view: MTKView
    ) throws -> (
        shadowAndUI: (ShadowResources, UIResources),
        overlayAndSWF: (WorldOverlayResources, SWFPassResources)
    ) {
        try (
            (
                makeShadowResources(device: device),
                makeUIResources(device: device, view: view)
            ),
            (
                makeWorldOverlayResources(device: device, view: view),
                makeSWFPassResources(device: device, view: view)
            )
        )
    }

    /// Argument table sized for the whole scene pass. Buffers: vertices,
    /// frame + draw uniforms, terrain weights, instance transforms, particles.
    /// Textures: base diffuse + the terrain layer array.
    static func makeArgumentTable(device: MTLDevice) throws -> MTL4ArgumentTable {
        let descriptor = MTL4ArgumentTableDescriptor()
        // Highest buffer index is the world-overlay vertex stream (#422).
        descriptor.maxBufferBindCount = BufferIndex.morphDeltas.rawValue + 1
        // Base diffuse + terrain layer array + sun-shadow cascade array + the
        // UI glyph/solid atlas + the SWF bitmap and gradient-ramp slots.
        descriptor.maxTextureBindCount = TextureIndex.swfGradient.rawValue + 1
        // Trilinear + shadow-compare + UI clamp + SWF repeat.
        descriptor.maxSamplerStateBindCount = 4
        return try device.makeArgumentTable(descriptor: descriptor)
    }

    nonisolated static func makeUniformBuffer(
        device: MTLDevice,
        length: Int,
        label: String
    ) throws -> MTLBuffer {
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared)
        else { throw RendererError.bufferAllocationFailed }
        buffer.label = label
        return buffer
    }

    /// Per-frame uniform ring: one aligned slot per in-flight frame.
    static func makeFrameUniformBuffer(device: MTLDevice) throws -> MTLBuffer {
        try makeUniformBuffer(
            device: device,
            length: alignedFrameUniformsSize * maxFramesInFlight,
            label: "FrameUniforms"
        )
    }

    static func makePipelines(
        device: MTLDevice,
        view: MTKView
    ) throws -> RenderPipelines {
        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.defaultLibraryMissing
        }
        let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())

        func makeVariant(
            alphaTest: Bool,
            skinned: Bool = false,
            morphed: Bool = false
        ) throws -> MTLRenderPipelineState {
            let vertexFunction = MTL4LibraryFunctionDescriptor()
            vertexFunction.library = library
            vertexFunction.name = morphed ? "morphedSkinnedMeshVertex"
                : (skinned ? "skinnedMeshVertex" : "staticMeshVertex")

            let specialized = specializedFragment(
                "staticMeshFragment", library: library, debugView: false, alphaTest: alphaTest
            )

            let descriptor = MTL4RenderPipelineDescriptor()
            descriptor.label = (morphed ? "MorphedSkinnedMesh"
                : (skinned ? "SkinnedMesh" : "StaticMesh"))
                + (alphaTest ? "AlphaTest" : "Opaque")
            descriptor.rasterSampleCount = view.sampleCount
            descriptor.vertexFunctionDescriptor = vertexFunction
            descriptor.fragmentFunctionDescriptor = specialized
            descriptor.vertexDescriptor = morphed ? MorphVertexLayout.vertexDescriptor()
                : (skinned
                    ? SkinVertexLayout.vertexDescriptor() : StaticVertexLayout.vertexDescriptor())
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            return try compiler.makeRenderPipelineState(descriptor: descriptor)
        }

        return try RenderPipelines(
            sky: makeSkyPipeline(library: library, compiler: compiler, view: view),
            opaque: makeVariant(alphaTest: false),
            alphaTest: makeVariant(alphaTest: true),
            skinnedOpaque: makeVariant(alphaTest: false, skinned: true),
            skinnedAlphaTest: makeVariant(alphaTest: true, skinned: true),
            morphedSkinnedOpaque: makeVariant(
                alphaTest: false, skinned: true, morphed: true
            ),
            morphedSkinnedAlphaTest: makeVariant(
                alphaTest: true, skinned: true, morphed: true
            ),
            grass: makeGrassPipeline(library: library, compiler: compiler, view: view),
            terrain: makeTerrainPipeline(library: library, compiler: compiler, view: view),
            water: makeWaterPipeline(library: library, compiler: compiler, view: view),
            particles: makeParticlePipelines(
                library: library, compiler: compiler, view: view
            ),
            debug: makeDebugPipelines(library: library, compiler: compiler, view: view)
        )
    }

    private static func makeParticlePipelines(
        library: MTLLibrary,
        compiler: MTL4Compiler,
        view: MTKView
    ) throws -> ParticlePipelines {
        try ParticlePipelines(
            alpha: makeParticlePipeline(
                library: library, compiler: compiler, view: view, mode: .alpha
            ),
            additive: makeParticlePipeline(
                library: library, compiler: compiler, view: view, mode: .additive
            ),
            additiveOne: makeParticlePipeline(
                library: library, compiler: compiler, view: view, mode: .additiveOne
            ),
            multiply: makeParticlePipeline(
                library: library, compiler: compiler, view: view, mode: .multiply
            )
        )
    }

    private static func makeSkyPipeline(
        library: MTLLibrary,
        compiler: MTL4Compiler,
        view: MTKView
    ) throws -> MTLRenderPipelineState {
        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.library = library
        vertexFunction.name = "skyVertex"
        let fragmentFunction = MTL4LibraryFunctionDescriptor()
        fragmentFunction.library = library
        fragmentFunction.name = "skyFragment"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "ProceduralSky"
        descriptor.rasterSampleCount = view.sampleCount
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeWaterPipeline(
        library: MTLLibrary,
        compiler: MTL4Compiler,
        view: MTKView
    ) throws -> MTLRenderPipelineState {
        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.library = library
        vertexFunction.name = "waterVertex"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "CellWaterBlend"
        descriptor.rasterSampleCount = view.sampleCount
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = specializedFragment(
            "waterFragment", library: library, debugView: false
        )
        descriptor.vertexDescriptor = StaticVertexLayout.vertexDescriptor()
        guard let color = descriptor.colorAttachments[0] else {
            throw RendererError.pipelineAttachmentMissing
        }
        color.pixelFormat = view.colorPixelFormat
        color.blendingState = .enabled
        color.sourceRGBBlendFactor = .sourceAlpha
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.rgbBlendOperation = .add
        color.sourceAlphaBlendFactor = .one
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        color.alphaBlendOperation = .add
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeParticlePipeline(
        library: MTLLibrary,
        compiler: MTL4Compiler,
        view: MTKView,
        mode: ParticleBlendMode
    ) throws -> MTLRenderPipelineState {
        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.library = library
        vertexFunction.name = "particleVertex"
        let fragmentFunction = MTL4LibraryFunctionDescriptor()
        fragmentFunction.library = library
        fragmentFunction.name = "particleFragment"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "Particles.\(mode)"
        descriptor.rasterSampleCount = view.sampleCount
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = fragmentFunction
        guard let color = descriptor.colorAttachments[0] else {
            throw RendererError.pipelineAttachmentMissing
        }
        color.pixelFormat = view.colorPixelFormat
        color.blendingState = .enabled
        switch mode {
        case .alpha:
            color.sourceRGBBlendFactor = .sourceAlpha
            color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        case .additive:
            color.sourceRGBBlendFactor = .sourceAlpha
            color.destinationRGBBlendFactor = .one
        case .additiveOne:
            color.sourceRGBBlendFactor = .one
            color.destinationRGBBlendFactor = .one
        case .multiply:
            color.sourceRGBBlendFactor = .destinationColor
            color.destinationRGBBlendFactor = .zero
        }
        color.rgbBlendOperation = .add
        color.sourceAlphaBlendFactor = .one
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        color.alphaBlendOperation = .add
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
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

    /// Water tests opaque depth but does not write depth while blending.
    static func makeWaterDepthState(device: MTLDevice) throws -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.label = "WaterReadOnlyDepth"
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = false
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
