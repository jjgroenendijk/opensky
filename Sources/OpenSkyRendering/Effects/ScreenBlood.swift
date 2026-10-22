// The renderer's half of screen blood: textured quads over the world, under the
// menus and the UI. The runtime that decides what shows sits in the effects module
// (docs/rendering/visual-effects.md#blood).

import Metal
import MetalKit
import OpenSkyShaderTypes
import simd

/// One screen blood quad for one frame.
nonisolated public struct ScreenBloodSplat: Equatable, Sendable {
    nonisolated public enum Layer: Equatable, Sendable {
        case splatter
        case flare
    }

    /// 0-1 on each axis, y down.
    public var center: SIMD2<Float>
    /// The share of the screen height.
    public var size: Float
    public var rotation: Float
    public var opacity: Float
    public var layer: Layer

    public init(
        center: SIMD2<Float>, size: Float, rotation: Float, opacity: Float, layer: Layer
    ) {
        self.center = center
        self.size = size
        self.rotation = rotation
        self.opacity = opacity
        self.layer = layer
    }
}

/// The three textures the game settings name.
nonisolated public struct ScreenBloodTextures {
    public let color: MTLTexture
    public let alpha: MTLTexture
    public let flare: MTLTexture

    public init(color: MTLTexture, alpha: MTLTexture, flare: MTLTexture) {
        self.color = color
        self.alpha = alpha
        self.flare = flare
    }

    var allocations: [MTLAllocation] {
        [color, alpha, flare]
    }
}

/// The two pipelines, the vertex ring, and this frame's quads.
public final class ScreenBloodLayer {
    /// At most this many quads draw in one frame; the rest wait.
    nonisolated public static let quadLimit = 128
    nonisolated static let verticesPerQuad = 6

    let splatterPipeline: MTLRenderPipelineState
    let flarePipeline: MTLRenderPipelineState
    let vertexBuffer: MTLBuffer
    public internal(set) var splats: [ScreenBloodSplat] = []
    public internal(set) var textures: ScreenBloodTextures?
    public internal(set) var lastQuads = 0

    init(device: MTLDevice, library: MTLLibrary, view: MTKView, compiler: PipelineCache) throws {
        splatterPipeline = try Self.makePipeline(
            fragment: "screenBloodFragment", library: library, compiler: compiler, view: view
        )
        flarePipeline = try Self.makePipeline(
            fragment: "screenBloodFlareFragment", library: library, compiler: compiler, view: view
        )
        let length = Self.quadLimit * Self.verticesPerQuad * MemoryLayout<UIVertex>.stride
            * Renderer.maxFramesInFlight
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            throw RendererError.bufferAllocationFailed
        }
        buffer.label = "ScreenBloodVertices"
        vertexBuffer = buffer
    }

    /// The quads of `splats` in clip space, splatters before flares, for a viewport of
    /// `aspect` width over height.
    nonisolated static func vertices(_ splats: [ScreenBloodSplat], aspect: Float) -> [UIVertex] {
        let ordered = splats.filter { $0.layer == .splatter } + splats.filter { $0.layer == .flare }
        return ordered.prefix(quadLimit).flatMap { splat -> [UIVertex] in
            let center = SIMD2(splat.center.x * 2 - 1, 1 - splat.center.y * 2)
            let half = splat.size
            let (sine, cosine) = (sin(splat.rotation), cos(splat.rotation))
            func corner(_ unit: SIMD2<Float>) -> UIVertex {
                let turned = SIMD2(
                    unit.x * cosine - unit.y * sine, unit.x * sine + unit.y * cosine
                ) * half
                return UIVertex(
                    position: center + SIMD2(turned.x / max(aspect, 1e-3), turned.y),
                    uv: SIMD2((unit.x + 1) / 2, (1 - unit.y) / 2),
                    color: SIMD4(1, 1, 1, min(max(splat.opacity, 0), 1))
                )
            }
            let corners = [SIMD2<Float>(-1, -1), SIMD2(1, -1), SIMD2(1, 1), SIMD2(-1, 1)]
                .map(corner)
            return [corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]]
        }
    }

    /// Premultiplied over, the UI's blend.
    private static func makePipeline(
        fragment: String, library: MTLLibrary, compiler: PipelineCache, view: MTKView
    ) throws -> MTLRenderPipelineState {
        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.library = library
        vertexFunction.name = "screenBloodVertex"
        let fragmentFunction = MTL4LibraryFunctionDescriptor()
        fragmentFunction.library = library
        fragmentFunction.name = fragment
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "ScreenBlood \(fragment)"
        descriptor.rasterSampleCount = view.sampleCount
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = fragmentFunction
        guard let color = descriptor.colorAttachments[0] else {
            throw RendererError.pipelineAttachmentMissing
        }
        color.pixelFormat = view.colorPixelFormat
        color.blendingState = .enabled
        color.sourceRGBBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.sourceAlphaBlendFactor = .one
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
    }
}

extension Renderer {
    /// Replaces the screen blood quads. Nil textures draw nothing.
    public func setScreenBlood(_ splats: [ScreenBloodSplat], textures: ScreenBloodTextures?) {
        let layer = effects.screenBlood
        if textures?.color !== layer.textures?.color || textures?.flare !== layer.textures?.flare {
            let retiring = layer.textures?.allocations ?? []
            layer.textures = textures
            if let textures {
                residencySet.addAllocations(textures.allocations)
                residencySet.commit()
            }
            retireAllocations(retiring)
        }
        layer.splats = textures == nil ? [] : splats
    }

    /// Encodes the screen blood after the world, before the SWF menus and the UI.
    func encodeScreenBlood(descriptor: MTL4RenderPassDescriptor, state: inout ScenePassState) {
        let layer = effects.screenBlood
        layer.lastQuads = 0
        guard
            let textures = layer.textures, !layer.splats.isEmpty,
            let target = descriptor.colorAttachments[0].texture, target.height > 0
        else { return }
        let aspect = Float(target.width) / Float(target.height)
        let vertices = ScreenBloodLayer.vertices(layer.splats, aspect: aspect)
        let stride = MemoryLayout<UIVertex>.stride
        let offset = state.slot * ScreenBloodLayer.quadLimit * ScreenBloodLayer.verticesPerQuad
            * stride
        vertices.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            layer.vertexBuffer.contents().advanced(by: offset)
                .copyMemory(from: base, byteCount: bytes.count)
        }
        let encoder = state.encoder
        encoder.setDepthStencilState(uiResources.depthState)
        encoder.setCullMode(.none)
        argumentTable.setSamplerState(sampler.gpuResourceID, index: SamplerIndex.trilinear.rawValue)
        argumentTable.setAddress(
            layer.vertexBuffer.gpuAddress + UInt64(offset), index: BufferIndex.uiVertices.rawValue
        )
        let splatters = min(
            layer.splats.count { $0.layer == .splatter }, ScreenBloodLayer.quadLimit
        )
        let flares = vertices.count / ScreenBloodLayer.verticesPerQuad - splatters
        if splatters > 0 {
            encoder.setRenderPipelineState(layer.splatterPipeline)
            argumentTable.setTexture(
                textures.color.gpuResourceID, index: TextureIndex.screenBloodColor.rawValue
            )
            argumentTable.setTexture(
                textures.alpha.gpuResourceID, index: TextureIndex.screenBloodAlpha.rawValue
            )
            encoder.drawPrimitives(
                primitiveType: .triangle, vertexStart: 0,
                vertexCount: splatters * ScreenBloodLayer.verticesPerQuad
            )
            state.stats.drawCalls += 1
        }
        if flares > 0 {
            encoder.setRenderPipelineState(layer.flarePipeline)
            argumentTable.setTexture(
                textures.flare.gpuResourceID, index: TextureIndex.screenBloodColor.rawValue
            )
            encoder.drawPrimitives(
                primitiveType: .triangle,
                vertexStart: splatters * ScreenBloodLayer.verticesPerQuad,
                vertexCount: flares * ScreenBloodLayer.verticesPerQuad
            )
            state.stats.drawCalls += 1
        }
        layer.lastQuads = splatters + flares
    }
}
