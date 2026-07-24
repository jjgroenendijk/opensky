// Static GPU objects for the SWF display-list layer (M8.2.4), built once at
// renderer init: the content + mask pipelines, the counting-stencil states
// for clip layers, the repeat sampler for tiled bitmap fills, and the 1x1
// fallback textures that keep every argument bound on non-bitmap/non-gradient
// draws. Per-movie resources (vertex data, bitmap textures, ramp, rings) live
// in SWFMovieResources (RendererSWFMovie.swift); encode in RendererSWFPass.

import Metal
import MetalKit

/// Draw accounting for the most recently encoded SWF layer, mirrored to
/// `Renderer.lastSWFDrawStats` (house style: exact counts, written per frame).
nonisolated struct SWFDrawStats: Equatable {
    var drawCalls = 0
    var triangles = 0
    var glyphs = 0
    /// Stencil-only clip draws (increments + decrements).
    var maskDraws = 0
    /// Items that could not draw: unresolved fonts, missing characters,
    /// degenerate fill matrices, characters skipped by the scene flattener.
    var skippedItems = 0
}

/// The SWF layer's long-lived state: static GPU objects plus the swappable
/// movie package. A class so renderer extensions can mutate movie/enable
/// state without adding stored properties to Renderer itself.
nonisolated final class SWFPassResources {
    let contentPipeline: MTLRenderPipelineState
    let maskPipeline: MTLRenderPipelineState
    /// Content draws: depth always/no write, stencil pass where the value
    /// equals the active-clip count (reference set per draw).
    let contentDepthState: MTLDepthStencilState
    /// Mask draws: stencil increment/decrement-clamp, color left untouched by
    /// the mask fragment's zero premultiplied output.
    let maskIncrementState: MTLDepthStencilState
    let maskDecrementState: MTLDepthStencilState
    let repeatSampler: MTLSamplerState
    /// 1x1 opaque white rgba8 — bound at TextureIndexSWFBitmap when a draw
    /// has no bitmap fill so the argument stays valid.
    let whiteTexture: MTLTexture
    /// 1x1 fallback ramp — bound at TextureIndexSWFGradient when the movie
    /// has no gradient fills.
    let fallbackRamp: MTLTexture

    /// A/B toggle mirrored by `Renderer.swfEnabled`.
    var enabled = true
    var movie: SWFMovieResources?
    var lastDrawStats = SWFDrawStats()
    /// Bumped per setSWFMovie: namespaces glyph-atlas font keys so two loaded
    /// movies (or reloads) never collide in the shared atlas cache.
    var generation = 0

    init(
        contentPipeline: MTLRenderPipelineState,
        maskPipeline: MTLRenderPipelineState,
        contentDepthState: MTLDepthStencilState,
        maskIncrementState: MTLDepthStencilState,
        maskDecrementState: MTLDepthStencilState,
        repeatSampler: MTLSamplerState,
        whiteTexture: MTLTexture,
        fallbackRamp: MTLTexture
    ) {
        self.contentPipeline = contentPipeline
        self.maskPipeline = maskPipeline
        self.contentDepthState = contentDepthState
        self.maskIncrementState = maskIncrementState
        self.maskDecrementState = maskDecrementState
        self.repeatSampler = repeatSampler
        self.whiteTexture = whiteTexture
        self.fallbackRamp = fallbackRamp
    }
}

extension Renderer {
    /// 256-byte-aligned per-draw slot in the SWF uniform ring.
    static let alignedSWFUniformsSize = (MemoryLayout<SWFDrawUniforms>.size + 0xFF) & -0x100

    static func makeSWFPassResources(
        device: MTLDevice,
        view: MTKView
    ) throws -> SWFPassResources {
        try SWFPassResources(
            contentPipeline: makeSWFPipeline(
                device: device, view: view, fragment: "swfFragment", label: "SWFContent"
            ),
            maskPipeline: makeSWFPipeline(
                device: device, view: view, fragment: "swfMaskFragment", label: "SWFMask"
            ),
            contentDepthState: makeSWFContentDepthState(device: device),
            maskIncrementState: makeSWFMaskDepthState(device: device, increment: true),
            maskDecrementState: makeSWFMaskDepthState(device: device, increment: false),
            repeatSampler: makeSWFRepeatSampler(device: device),
            whiteTexture: makeSWFSolidTexture(
                device: device, pixel: [255, 255, 255, 255], label: "SWFWhiteFallback"
            ),
            fallbackRamp: makeSWFSolidTexture(
                device: device, pixel: [255, 255, 255, 255], label: "SWFRampFallback"
            )
        )
    }

    private static func makeSWFPipeline(
        device: MTLDevice,
        view: MTKView,
        fragment: String,
        label: String
    ) throws -> MTLRenderPipelineState {
        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.defaultLibraryMissing
        }
        let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())
        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.library = library
        vertexFunction.name = "swfVertex"
        let fragmentFunction = MTL4LibraryFunctionDescriptor()
        fragmentFunction.library = library
        fragmentFunction.name = fragment
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = label
        descriptor.rasterSampleCount = view.sampleCount
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = fragmentFunction
        guard let color = descriptor.colorAttachments[0] else {
            throw RendererError.pipelineAttachmentMissing
        }
        // Premultiplied source-one over blend, matching the UI pass. The mask
        // fragment outputs zero, which leaves the destination untouched under
        // this blend — no color-write-mask special case needed.
        color.pixelFormat = view.colorPixelFormat
        color.blendingState = .enabled
        color.sourceRGBBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.rgbBlendOperation = .add
        color.sourceAlphaBlendFactor = .one
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        color.alphaBlendOperation = .add
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Content: draw over everything (depth always, no write); pass only
    /// where the stencil equals the active-clip count (reference per draw).
    private static func makeSWFContentDepthState(
        device: MTLDevice
    ) throws -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.label = "SWFContentStencilEqual"
        descriptor.depthCompareFunction = .always
        descriptor.isDepthWriteEnabled = false
        let stencil = MTLStencilDescriptor()
        stencil.stencilCompareFunction = .equal
        stencil.stencilFailureOperation = .keep
        stencil.depthFailureOperation = .keep
        stencil.depthStencilPassOperation = .keep
        stencil.readMask = 0xFF
        stencil.writeMask = 0x00
        descriptor.frontFaceStencil = stencil
        descriptor.backFaceStencil = stencil
        guard let state = device.makeDepthStencilState(descriptor: descriptor) else {
            throw RendererError.depthStateAllocationFailed
        }
        return state
    }

    /// Masks: unconditional stencil increment (begin clip) or decrement (end
    /// clip) clamped at the range bounds, counting overlapping clip layers.
    private static func makeSWFMaskDepthState(
        device: MTLDevice,
        increment: Bool
    ) throws -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.label = increment ? "SWFMaskIncrement" : "SWFMaskDecrement"
        descriptor.depthCompareFunction = .always
        descriptor.isDepthWriteEnabled = false
        let stencil = MTLStencilDescriptor()
        stencil.stencilCompareFunction = .always
        stencil.stencilFailureOperation = .keep
        stencil.depthFailureOperation = .keep
        stencil.depthStencilPassOperation = increment ? .incrementClamp : .decrementClamp
        stencil.readMask = 0xFF
        stencil.writeMask = 0xFF
        descriptor.frontFaceStencil = stencil
        descriptor.backFaceStencil = stencil
        guard let state = device.makeDepthStencilState(descriptor: descriptor) else {
            throw RendererError.depthStateAllocationFailed
        }
        return state
    }

    /// Linear repeat sampler for tiled bitmap fills (0x40/0x42).
    private static func makeSWFRepeatSampler(device: MTLDevice) throws -> MTLSamplerState {
        let descriptor = MTLSamplerDescriptor()
        descriptor.label = "SWFBitmapRepeat"
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.sAddressMode = .repeat
        descriptor.tAddressMode = .repeat
        descriptor.supportArgumentBuffers = true
        guard let sampler = device.makeSamplerState(descriptor: descriptor) else {
            throw RendererError.samplerAllocationFailed
        }
        return sampler
    }

    private static func makeSWFSolidTexture(
        device: MTLDevice,
        pixel: [UInt8],
        label: String
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.textureAllocationFailed
        }
        texture.label = label
        pixel.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: 4
            )
        }
        return texture
    }
}
