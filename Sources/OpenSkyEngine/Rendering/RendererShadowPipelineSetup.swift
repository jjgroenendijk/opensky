// Sun-shadow pipeline, sampler and cascade-array construction, split from
// RendererSetup.swift (file-length limits, same satellite pattern as
// RendererScenePipelineSetup.swift). Depth-only: these pipelines carry no color
// attachment, so their depth format binds at pass time.

import Metal
import OpenSkyShaderTypes

extension Renderer {
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
            skinned: Bool,
            morphed: Bool = false
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
            descriptor.vertexDescriptor = morphed ? MorphVertexLayout.vertexDescriptor()
                : (skinned
                    ? SkinVertexLayout.vertexDescriptor() : StaticVertexLayout.vertexDescriptor())
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
            morphedSkinned: make(
                label: "ShadowMorphedSkinned", vertex: "shadowMorphedSkinnedVertex",
                fragment: nil, skinned: true, morphed: true
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
}
