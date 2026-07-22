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
    let grass: MTLRenderPipelineState
    let terrain: MTLRenderPipelineState
    let water: MTLRenderPipelineState
    let particles: ParticlePipelines
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
    static var nearPlane: Float {
        10
    }

    static var farPlane: Float {
        65536
    }

    /// Sun-shadow far bound (high quality): 3 exterior cells (4096 units each),
    /// matching the resident streaming grid. Casters beyond it are un-shadowed
    /// by design.
    static var shadowDistance: Float {
        12288
    }

    /// Low-quality sun-shadow far bound: 2 exterior cells. Shorter range +
    /// fewer cascades (see shadowCascadeCount) trade shadow reach for cost.
    static var shadowDistanceLow: Float {
        8192
    }

    /// Light near plane extended backwards (toward the sun) by this many world
    /// units so casters between the sun and a cascade slice still render.
    static var shadowCasterBackup: Float {
        12288
    }

    /// Blend between uniform + logarithmic cascade splits (0 = uniform).
    static var shadowSplitLambda: Float {
        0.7
    }

    /// Raster depth bias for the shadow pre-pass: constant + slope-scaled,
    /// no clamp. Trades a little peter-panning for acne removal; tune against
    /// the real install if either shows.
    static var shadowDepthBias: Float {
        2
    }

    static var shadowSlopeScale: Float {
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

    /// Argument table sized for the whole scene pass. Buffers: vertices,
    /// frame + draw uniforms, terrain weights, instance transforms, particles.
    /// Textures: base diffuse + the terrain layer array.
    static func makeArgumentTable(device: MTLDevice) throws -> MTL4ArgumentTable {
        let descriptor = MTL4ArgumentTableDescriptor()
        // Highest buffer index is the UI uniforms slot (M8.1.1).
        descriptor.maxBufferBindCount = BufferIndex.uiUniforms.rawValue + 1
        // Base diffuse + terrain layer array + sun-shadow cascade array + the
        // UI glyph/solid atlas.
        descriptor.maxTextureBindCount = 1 + TerrainConstant.maxLayers.rawValue + 1 + 1
        // Trilinear + shadow-compare + UI.
        descriptor.maxSamplerStateBindCount = 3
        return try device.makeArgumentTable(descriptor: descriptor)
    }

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

        func makeVariant(alphaTest: Bool, skinned: Bool = false) throws -> MTLRenderPipelineState {
            let vertexFunction = MTL4LibraryFunctionDescriptor()
            vertexFunction.library = library
            vertexFunction.name = skinned ? "skinnedMeshVertex" : "staticMeshVertex"

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
            descriptor.label = (skinned ? "SkinnedMesh" : "StaticMesh")
                + (alphaTest ? "AlphaTest" : "Opaque")
            descriptor.rasterSampleCount = view.sampleCount
            descriptor.vertexFunctionDescriptor = vertexFunction
            descriptor.fragmentFunctionDescriptor = specialized
            descriptor.vertexDescriptor = skinned
                ? SkinVertexLayout.vertexDescriptor() : StaticVertexLayout.vertexDescriptor()
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            return try compiler.makeRenderPipelineState(descriptor: descriptor)
        }

        return try RenderPipelines(
            sky: makeSkyPipeline(library: library, compiler: compiler, view: view),
            opaque: makeVariant(alphaTest: false),
            alphaTest: makeVariant(alphaTest: true),
            skinnedOpaque: makeVariant(alphaTest: false, skinned: true),
            skinnedAlphaTest: makeVariant(alphaTest: true, skinned: true),
            grass: makeGrassPipeline(library: library, compiler: compiler, view: view),
            terrain: makeTerrainPipeline(library: library, compiler: compiler, view: view),
            water: makeWaterPipeline(library: library, compiler: compiler, view: view),
            particles: makeParticlePipelines(
                library: library, compiler: compiler, view: view
            )
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

    /// Builds the shadow pipelines + compare sampler + cascade array together.
    static func makeShadowResources(device: MTLDevice) throws -> ShadowResources {
        try ShadowResources(
            pipelines: makeShadowPipelines(device: device),
            sampler: makeShadowSampler(device: device),
            map: makeShadowMap(device: device)
        )
    }

    /// Depth-only sun-shadow pipelines. No color attachment; depth format
    /// binds at pass time (the pass has nothing else to infer the target from,
    /// unlike the scene pipelines which carry a color attachment).
    private static func makeShadowPipelines(
        device: MTLDevice
    ) throws -> ShadowPipelines {
        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.defaultLibraryMissing
        }
        let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())

        func make(
            label: String,
            vertex: String,
            fragment: String?,
            skinned: Bool
        ) throws -> MTLRenderPipelineState {
            let vertexFunction = MTL4LibraryFunctionDescriptor()
            vertexFunction.library = library
            vertexFunction.name = vertex
            let descriptor = MTL4RenderPipelineDescriptor()
            descriptor.label = label
            descriptor.rasterSampleCount = 1
            descriptor.vertexFunctionDescriptor = vertexFunction
            if let fragment {
                let fragmentFunction = MTL4LibraryFunctionDescriptor()
                fragmentFunction.library = library
                fragmentFunction.name = fragment
                descriptor.fragmentFunctionDescriptor = fragmentFunction
            }
            // Terrain casts through the static interleaved stream (position at
            // buffer 0); the splat-weight stream is irrelevant to depth.
            descriptor.vertexDescriptor = skinned
                ? SkinVertexLayout.vertexDescriptor() : StaticVertexLayout.vertexDescriptor()
            // No color attachment + depth-only: the depth format binds at pass
            // time (MTL4RenderPipelineDescriptor carries no depth format, same
            // as the scene pipelines).
            return try compiler.makeRenderPipelineState(descriptor: descriptor)
        }

        return try ShadowPipelines(
            staticCaster: make(
                label: "ShadowStatic", vertex: "shadowStaticVertex",
                fragment: nil, skinned: false
            ),
            alphaTest: make(
                label: "ShadowAlphaTest", vertex: "shadowStaticVertex",
                fragment: "shadowAlphaTestFragment", skinned: false
            ),
            skinned: make(
                label: "ShadowSkinned", vertex: "shadowSkinnedVertex",
                fragment: nil, skinned: true
            ),
            terrain: make(
                label: "ShadowTerrain", vertex: "shadowTerrainVertex",
                fragment: nil, skinned: false
            )
        )
    }

    /// Depth-compare sampler for shadow PCF: linear filtering runs the 2x2
    /// hardware comparison, clamp-to-edge keeps out-of-map taps lit.
    private static func makeShadowSampler(device: MTLDevice) throws -> MTLSamplerState {
        let descriptor = MTLSamplerDescriptor()
        descriptor.label = "ShadowCompare"
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        descriptor.compareFunction = .less
        descriptor.supportArgumentBuffers = true
        guard let sampler = device.makeSamplerState(descriptor: descriptor) else {
            throw RendererError.samplerAllocationFailed
        }
        return sampler
    }

    /// One shared cascade array: depth32Float, 2D array of
    /// ShadowConstantCascadeCount slices, private (GPU-only) storage.
    private static func makeShadowMap(device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = .depth32Float
        descriptor.width = ShadowConstant.mapResolution.rawValue
        descriptor.height = ShadowConstant.mapResolution.rawValue
        descriptor.arrayLength = ShadowConstant.cascadeCount.rawValue
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.textureAllocationFailed
        }
        texture.label = "SunShadowCascades"
        return texture
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
        let fragmentFunction = MTL4LibraryFunctionDescriptor()
        fragmentFunction.library = library
        fragmentFunction.name = "waterFragment"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "CellWaterBlend"
        descriptor.rasterSampleCount = view.sampleCount
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = fragmentFunction
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
