// The renderer's half of visual effects: short-lived world models (effect art,
// debris, hazard models) drawn through the instanced scene path, and membrane
// overlays drawn additively over an actor's meshes. The runtimes that decide what
// is live sit above; they hand this layer placements and membranes each frame.
// See docs/rendering/visual-effects.md.

import Metal
import MetalKit
import OpenSkyShaderTypes
import simd

/// What a membrane covers: the player's body or one placed actor.
nonisolated public enum MembraneTarget: Hashable, Sendable {
    case player
    /// The `ACHR` FormID the actor's placements carry as `RenderPlacement.owner`.
    case actor(UInt32)
}

/// One membrane overlay for one frame. Colors are linear and already scaled by alpha.
nonisolated public struct MembraneDraw: Equatable, Sendable {
    public let target: MembraneTarget
    public let fill: SIMD3<Float>
    public let edge: SIMD3<Float>
    /// The exponent that narrows the edge glow to grazing angles.
    public let edgeFalloff: Float

    public init(
        target: MembraneTarget,
        fill: SIMD3<Float>,
        edge: SIMD3<Float>,
        edgeFalloff: Float
    ) {
        self.target = target
        self.fill = fill
        self.edge = edge
        self.edgeFalloff = edgeFalloff
    }
}

/// One texture's decals in the shared decal buffer.
nonisolated public struct DecalBatch {
    public let texture: MTLTexture
    public let instances: [DecalInstance]

    public init(texture: MTLTexture, instances: [DecalInstance]) {
        self.texture = texture
        self.instances = instances
    }
}

/// The effect models, the membrane pipelines, and their uniform ring.
public final class EffectLayer {
    /// At most this many membranes draw in one frame; the rest wait.
    public static let membraneLimit = 16
    static let uniformStride = (MemoryLayout<MembraneUniforms>.size + 0xFF) & -0x100

    /// The effect models of the current frame. Set through `Renderer.setEffectPlacements`.
    public internal(set) var scene = RenderScene(instances: [])
    public var membranes: [MembraneDraw] = []
    /// The loading screen's object. While set, the world does not draw.
    public internal(set) var loadingCover: RenderScene?
    /// Membranes the last frame drew, for the readout.
    public internal(set) var lastMembraneDraws = 0
    /// The particle systems of effect models, simulated like the scene's.
    public internal(set) var particles: [ParticlePlayback] = []
    /// The decals, one batch per texture, in `decalBuffer` order.
    public internal(set) var decalBatches: [DecalBatch] = []
    var decalBuffer: MTLBuffer?
    /// Decals the last frame drew, for the readout.
    public internal(set) var lastDecalDraws = 0

    let staticPipeline: MTLRenderPipelineState
    let skinnedPipeline: MTLRenderPipelineState
    let morphedPipeline: MTLRenderPipelineState
    let decalPipeline: MTLRenderPipelineState
    let depthState: MTLDepthStencilState
    let uniformBuffer: MTLBuffer

    init(
        device: MTLDevice, library: MTLLibrary, view: MTKView, compiler: PipelineCache
    ) throws {
        func make(
            _ vertex: String,
            _ layout: MTLVertexDescriptor
        ) throws -> MTLRenderPipelineState {
            try Self.makePipeline(
                vertex: vertex, layout: layout, library: library, compiler: compiler, view: view
            )
        }
        staticPipeline = try make("staticMeshVertex", StaticVertexLayout.vertexDescriptor())
        skinnedPipeline = try make("skinnedMeshVertex", SkinVertexLayout.vertexDescriptor())
        morphedPipeline = try make(
            "morphedSkinnedMeshVertex", MorphVertexLayout.vertexDescriptor()
        )
        decalPipeline = try Self.makeDecalPipeline(
            library: library, compiler: compiler, view: view
        )
        let depth = MTLDepthStencilDescriptor()
        depth.label = "MembraneDepth"
        depth.depthCompareFunction = .lessEqual
        depth.isDepthWriteEnabled = false
        guard let state = device.makeDepthStencilState(descriptor: depth) else {
            throw RendererError.depthStateAllocationFailed
        }
        depthState = state
        guard
            let buffer = device.makeBuffer(
                length: Self.uniformStride * Self.membraneLimit * Renderer.maxFramesInFlight,
                options: .storageModeShared
            )
        else { throw RendererError.bufferAllocationFailed }
        buffer.label = "MembraneUniforms"
        uniformBuffer = buffer
    }

    /// Blends over the surface by the decal's alpha.
    private static func makeDecalPipeline(
        library: MTLLibrary,
        compiler: PipelineCache,
        view: MTKView
    ) throws -> MTLRenderPipelineState {
        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.library = library
        vertexFunction.name = "decalVertex"
        let fragment = MTL4LibraryFunctionDescriptor()
        fragment.library = library
        fragment.name = "decalFragment"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "Decal"
        descriptor.rasterSampleCount = view.sampleCount
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = fragment
        guard let color = descriptor.colorAttachments[0] else {
            throw RendererError.pipelineAttachmentMissing
        }
        color.pixelFormat = view.colorPixelFormat
        color.blendingState = .enabled
        color.sourceRGBBlendFactor = .sourceAlpha
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.sourceAlphaBlendFactor = .zero
        color.destinationAlphaBlendFactor = .one
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Additive: the membrane only ever brightens what is under it.
    private static func makePipeline(
        vertex: String,
        layout: MTLVertexDescriptor,
        library: MTLLibrary,
        compiler: PipelineCache,
        view: MTKView
    ) throws -> MTLRenderPipelineState {
        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.library = library
        vertexFunction.name = vertex
        let fragment = MTL4LibraryFunctionDescriptor()
        fragment.library = library
        fragment.name = "membraneFragment"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "Membrane \(vertex)"
        descriptor.rasterSampleCount = view.sampleCount
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = fragment
        descriptor.vertexDescriptor = layout
        guard let color = descriptor.colorAttachments[0] else {
            throw RendererError.pipelineAttachmentMissing
        }
        color.pixelFormat = view.colorPixelFormat
        color.blendingState = .enabled
        color.sourceRGBBlendFactor = .one
        color.destinationRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .zero
        color.destinationAlphaBlendFactor = .one
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
    }
}
