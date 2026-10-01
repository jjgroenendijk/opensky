// Static GPU objects for the SWF layer, built at init: content and mask pipelines,
// stencil states for clip layers, a repeat sampler, and 1x1 fallback textures. Per-movie
// resources live in RendererSWFMovie.swift.

import Metal
import MetalKit
import OpenSkyFormatsSWF
import OpenSkyShaderTypes

/// Draw accounting for the most recently encoded SWF layer, mirrored to
/// `Renderer.lastSWFDrawStats` (house style: exact counts, written per frame).
nonisolated public struct SWFDrawStats: Equatable, Sendable {
    public var drawCalls = 0
    public var triangles = 0
    public var glyphs = 0
    /// Stencil-only clip draws (increments + decrements).
    public var maskDraws = 0
    /// Items that could not draw: unresolved fonts, missing characters,
    /// degenerate fill matrices, characters skipped by the scene flattener.
    public var skippedItems = 0

    public init(
        drawCalls: Int = 0,
        triangles: Int = 0,
        glyphs: Int = 0,
        maskDraws: Int = 0,
        skippedItems: Int = 0
    ) {
        self.drawCalls = drawCalls
        self.triangles = triangles
        self.glyphs = glyphs
        self.maskDraws = maskDraws
        self.skippedItems = skippedItems
    }
}

/// The SWF layer's long-lived state: static GPU objects plus the swappable
/// movie package. A class so renderer extensions can mutate movie/enable
/// state without adding stored properties to Renderer itself.
nonisolated public final class SWFPassResources {
    public let contentPipeline: MTLRenderPipelineState
    public let maskPipeline: MTLRenderPipelineState
    /// Content draws: depth always/no write, stencil pass where the value
    /// equals the active-clip count (reference set per draw).
    public let contentDepthState: MTLDepthStencilState
    /// Mask draws: stencil increment/decrement-clamp, color left untouched by
    /// the mask fragment's zero premultiplied output.
    public let maskIncrementState: MTLDepthStencilState
    public let maskDecrementState: MTLDepthStencilState
    public let repeatSampler: MTLSamplerState
    /// 1x1 opaque white rgba8 — bound at TextureIndexSWFBitmap when a draw
    /// has no bitmap fill so the argument stays valid.
    public let whiteTexture: MTLTexture
    /// 1x1 fallback ramp — bound at TextureIndexSWFGradient when the movie
    /// has no gradient fills.
    public let fallbackRamp: MTLTexture

    /// A/B toggle mirrored by `Renderer.swfEnabled`.
    public var enabled = true
    /// Centered scale multiplier over the fit-to-viewport mapping.
    public var scale: Float = 1
    public var movie: SWFMovieResources?
    /// The AS2 runtime driving `movie`, when one was started. nil keeps the
    /// layer on the static frame-1 path.
    public var runtime: SWFMovieRuntime?
    public var lastDrawStats = SWFDrawStats()
    /// Bumped per setSWFMovie: namespaces glyph-atlas font keys so two loaded
    /// movies (or reloads) never collide in the shared atlas cache.
    public var generation = 0

    public init(
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
    nonisolated public static let alignedSWFUniformsSize = (MemoryLayout<SWFDrawUniforms>
        .size + 0xFF) &
        -0x100

    public static func makeSWFPassResources(
        device: MTLDevice,
        view: MTKView,
        library: MTLLibrary
    ) throws -> SWFPassResources {
        try SWFPassResources(
            contentPipeline: makeSWFPipeline(
                device: device, view: view, library: library,
                fragment: "swfFragment", label: "SWFContent"
            ),
            maskPipeline: makeSWFPipeline(
                device: device, view: view, library: library,
                fragment: "swfMaskFragment", label: "SWFMask"
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
        library: MTLLibrary,
        fragment: String,
        label: String
    ) throws -> MTLRenderPipelineState {
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
