// The renderer's half of visual effects: short-lived world models (effect art,
// debris, hazard models) drawn through the instanced scene path, and membrane
// overlays drawn additively over an actor's meshes. The runtimes that decide what
// is live sit above; they hand this layer placements and membranes each frame.
// See docs/rendering/visual-effects.md.

import Metal
import MetalKit
import OpenSkyRenderCore
import OpenSkyRenderResources
import OpenSkyShaderTypes
import simd

/// What a membrane covers: the player's body or one placed actor, or only the
/// unskinned meshes, such as a held weapon, of either.
nonisolated public enum MembraneTarget: Hashable, Sendable {
    case player
    /// The `ACHR` FormID the actor's placements carry as `RenderPlacement.owner`.
    case actor(UInt32)
    case playerWeapon
    case actorWeapon(UInt32)
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
    /// Drawn as a box onto the scene depth, so the mark wraps around a body.
    public let projected: Bool

    public init(texture: MTLTexture, instances: [DecalInstance], projected: Bool = false) {
        self.texture = texture
        self.instances = instances
        self.projected = projected
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
    /// The strength of the blood on each bloody weapon. Set through `Renderer.setBloodyWeapons`.
    public internal(set) var bloodyWeapons: [MembraneTarget: Float] = [:]
    /// The loading screen's object. While set, the world does not draw.
    public internal(set) var loadingCover: RenderScene?
    /// Wall time for the cover's particle systems, which run while a menu pauses the world.
    var loadingCoverClock = FrameSimClock()
    /// Membranes the last frame drew, for the readout.
    public internal(set) var lastMembraneDraws = 0
    /// The particle systems of effect models, simulated like the scene's.
    public internal(set) var particles: [ParticlePlayback] = []
    /// The decals, one batch per texture, in `decalBuffer` order.
    public internal(set) var decalBatches: [DecalBatch] = []
    var decalBuffer: MTLBuffer?
    /// Decals the last frame drew, for the readout.
    public internal(set) var lastDecalDraws = 0

    /// The unlit scene a menu draws in place of the world, such as the perk sky.
    public let menuScene: MenuSceneResources
    let staticPipeline: MTLRenderPipelineState
    let skinnedPipeline: MTLRenderPipelineState
    let morphedPipeline: MTLRenderPipelineState
    let decalPipeline: MTLRenderPipelineState
    let projectedDecalPipeline: MTLRenderPipelineState
    let depthState: MTLDepthStencilState
    /// No depth test: a projected decal's far faces lie behind the surface it marks.
    let projectedDecalDepthState: MTLDepthStencilState
    let uniformBuffer: MTLBuffer
    /// Screen blood quads (`ScreenBlood.swift`).
    public let screenBlood: ScreenBloodLayer
    /// A playing movie over the frame (`MovieLayer.swift`).
    public let movie: MovieLayer

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
            "decal", library: library, compiler: compiler, view: view
        )
        projectedDecalPipeline = try Self.makeDecalPipeline(
            "projectedDecal", library: library, compiler: compiler, view: view
        )
        screenBlood = try ScreenBloodLayer(
            device: device, library: library, view: view, compiler: compiler
        )
        movie = try MovieLayer(device: device, library: library, view: view, compiler: compiler)
        menuScene = try MenuSceneResources(
            device: device, library: library, view: view, compiler: compiler
        )
        let depth = MTLDepthStencilDescriptor()
        depth.label = "MembraneDepth"
        depth.depthCompareFunction = .lessEqual
        depth.isDepthWriteEnabled = false
        guard let state = device.makeDepthStencilState(descriptor: depth) else {
            throw RendererError.depthStateAllocationFailed
        }
        depthState = state
        let always = MTLDepthStencilDescriptor()
        always.label = "ProjectedDecalDepth"
        always.depthCompareFunction = .always
        always.isDepthWriteEnabled = false
        // The game marks only the skinned mesh, so the box draws where a skin set the bit.
        let skin = MTLStencilDescriptor()
        skin.stencilCompareFunction = .equal
        skin.readMask = MaterialDepthStates.skinStencilBit
        skin.writeMask = 0
        always.frontFaceStencil = skin
        always.backFaceStencil = skin
        guard let projected = device.makeDepthStencilState(descriptor: always) else {
            throw RendererError.depthStateAllocationFailed
        }
        projectedDecalDepthState = projected
        guard
            let buffer = device.makeBuffer(
                length: Self.uniformStride * Self.membraneLimit * GPUFactory.maxFramesInFlight,
                options: .storageModeShared
            )
        else { throw RendererError.bufferAllocationFailed }
        buffer.label = "MembraneUniforms"
        uniformBuffer = buffer
    }

    /// The buffers that stay resident for the renderer's life.
    var residentBuffers: [MTLAllocation] {
        [uniformBuffer, screenBlood.vertexBuffer, movie.vertexBuffer]
    }

    /// Blends over the surface by the decal's alpha.
    private static func makeDecalPipeline(
        _ name: String,
        library: MTLLibrary,
        compiler: PipelineCache,
        view: MTKView
    ) throws -> MTLRenderPipelineState {
        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.library = library
        vertexFunction.name = name + "Vertex"
        let fragment = MTL4LibraryFunctionDescriptor()
        fragment.library = library
        fragment.name = name + "Fragment"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = name
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
