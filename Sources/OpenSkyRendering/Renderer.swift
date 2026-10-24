// Metal 4 render loop; nil injected scene selects synthetic demo state for tests.

import Metal
import MetalKit
import OpenSkyDiagnostics
import OpenSkyPhysics
import OpenSkyRenderCore
import OpenSkyRenderResources
import OpenSkyShaderTypes
import QuartzCore
import simd

public final class Renderer: NSObject {
    // Members below default to internal (not private) where
    // RendererOffscreen.swift / RendererSetup.swift extend the loop
    // cross-file; the module boundary still hides them from callers.

    /// Uniform slots are 256-byte aligned so every ring offset satisfies
    /// Metal's buffer-offset alignment requirement. The per-draw ring is
    /// shared by static and terrain draws, so its slot fits either struct.
    public static let alignedFrameUniformsSize =
        (MemoryLayout<FrameUniforms>.size + 0xFF) & -0x100
    public static let alignedDrawUniformsSize =
        (max(
            MemoryLayout<DrawUniforms>.size,
            MemoryLayout<GrassDrawUniforms>.size,
            MemoryLayout<TerrainDrawUniforms>.size,
            MemoryLayout<WaterDrawUniforms>.size,
            MemoryLayout<ShadowDrawUniforms>.size
        )
            + 0xFF) & -0x100

    /// Near/far at Skyrim scale per docs/decisions/coordinates.md: near 10
    /// units (~14 cm; below ~1 unit destroys depth precision), far 16 cells.
    public let device: MTLDevice
    public let commandQueue: MTL4CommandQueue
    public let commandBuffer: MTL4CommandBuffer
    public let commandAllocators: [MTL4CommandAllocator]
    public let argumentTable: MTL4ArgumentTable
    public let skyPipeline: MTLRenderPipelineState
    public let cloudPipeline: MTLRenderPipelineState
    public let opaquePipeline: MTLRenderPipelineState
    public let alphaTestPipeline: MTLRenderPipelineState
    public let blendedPipeline: MTLRenderPipelineState
    public let skinnedBlendedPipelines: SkinnedBlendedPipelines
    public let additivePipelines: AdditivePipelines
    public let skinnedOpaquePipeline: MTLRenderPipelineState
    public let skinnedAlphaTestPipeline: MTLRenderPipelineState
    public let morphedSkinnedOpaquePipeline: MTLRenderPipelineState
    public let morphedSkinnedAlphaTestPipeline: MTLRenderPipelineState
    public let grassPipeline: MTLRenderPipelineState
    public let terrainPipeline: MTLRenderPipelineState
    public let waterPipeline: MTLRenderPipelineState
    public let particlePipelines: ParticlePipelines
    /// Render-debug twins of the five geometry paths, bound instead of their
    /// shipping counterparts while `renderDebug.mode` is not `.off`.
    public let debugPipelines: DebugRenderPipelines
    /// The scene pass's debug channel and drawn layers (`RendererDebugState.swift`).
    /// Not persisted, and not used offscreen unless `renderDebugAppliesOffscreen`.
    public var renderDebug = RenderDebugState()
    /// Whether an offscreen frame honours `renderDebug`. Off by default so
    /// screenshots and bench runs render the shipping frame however the dev
    /// shell is currently set; the device-gated debug-view tests turn it on.
    public var renderDebugAppliesOffscreen = false
    /// The colour an offscreen frame clears to; the sky, when drawn, covers it.
    public var offscreenBackground = SIMD3<Double>(0, 0, 0)
    /// The scene's own depth state: test and write.
    public var depthState: MTLDepthStencilState {
        materialDepthStates.state(test: true, write: true)
    }

    public let waterDepthState: MTLDepthStencilState
    let materialDepthStates: MaterialDepthStates
    public let sampler: MTLSamplerState
    /// Screen-space UI overlay: pipeline (fills and text premultiplied over the 3D frame,
    /// depth off), sampler, r8 glyph atlas, and the triple-buffered rings. Encode and
    /// resolve live in RendererUIPass.swift.
    public let uiResources: UIResources
    /// Depth-tested world-space debug overlay: blended pipeline, read-only
    /// depth state and fixed per-frame vertex ring (RendererOverlayPass.swift).
    public let worldOverlayResources: WorldOverlayResources
    /// Atlas revision last copied into the atlas texture; re-upload on change.
    public var uiUploadedAtlasRevision = -1
    /// SWF display-list layer: content and mask pipelines and counting stencil states.
    /// `setSWFMovie` swaps the movie; encode lives in RendererSWFPass.swift.
    public let swf: SWFPassResources
    /// The image-space composite pipeline, uniforms, and scene copy (RendererImageSpacePass.swift).
    public let imageSpacePass: ImageSpacePassResources
    /// Effect models and membrane overlays (`Effects/EffectLayer.swift`).
    public let effects: EffectLayer
    /// Sun-shadow pipelines + compare sampler + the shared cascade array
    /// (depth32Float, ShadowConstantCascadeCount slices). The array is created
    /// once, always resident, and bound at TextureIndexShadowMap every scene
    /// pass so validation stays clean even with shadows disabled.
    public let shadow: ShadowResources
    /// Sun shadow switch. Default on; ANDed
    /// with `shadowQuality` so it flips shadows without discarding the tier.
    public var sunShadowsEnabled = true
    /// The most real frames a second the live view draws; 0 is no cap.
    public var frameRateCap = 0
    /// Sun-shadow quality. `.off` skips the pass; `.low` and `.high` differ in cascades,
    /// range and PCF taps. Set on the main thread between frames.
    public var shadowQuality = ShadowQuality.high
    /// This frame's cascades, produced by encodeShadowPass, consumed by
    /// updateFrameUniforms. Empty when shadows are off/idle this frame.
    public var shadowCascades: [ShadowCascade] = []
    /// Whether encodeShadowPass rendered cascades this frame (drives the
    /// shader's shadowsEnabled flag). Reset every frame.
    public var shadowsActiveThisFrame = false
    /// Meshes whose bone palette was already copied into this frame's slot —
    /// shared guard so the shadow + scene pass never double-prepare (RenderMesh
    /// palette is identical across both passes within one frame).
    public var frameBonePrepared: Set<ObjectIdentifier> = []
    public var frameMorphPrepared: Set<ObjectIdentifier> = []
    /// Internal, not `private(set)`: `RendererSceneSwap.swift` owns the swap
    /// cross-file (same rule as the offscreen/setup satellites above).
    public var scene: RenderScene {
        didSet {
            shadowCasters = ShadowCasterBounds(scene: scene)
            actorGroupsByOwner = DrawGroup.actorGroupsByOwner(in: scene)
            sceneAllocations = scene.residencyAllocations
            emittanceRegions = scene.emittanceRegions
            gpuCull.isCurrent = false
            rayTracedShadows.isCurrent = false
            // A new cell shows other surfaces; old frames would ghost over them.
            upscale.resetPending = true
            mergeInstanceDeltas()
            pruneGrassMeshlets(keeping: scene.grass)
            pointLightPicks.removeAll(keepingCapacity: true)
        }
    }

    /// Set while a frame's culling and shadow work is committed ahead of its scene pass.
    var earlyFrameParts: GPUFrameParts?
    /// Joined once per frame, before the first pass.
    var frameDrawGroups = FrameDrawGroups()
    /// Lights that move every frame, such as a spell's light. Each draw takes them
    /// before the scene's nearest lights.
    public var transientPointLights: [RenderPointLight] = []
    /// Nearest point lights by lighting center, valid for the current scene.
    var pointLightPicks: [SIMD3<Float>: PointLightPick] = [:]
    static let pointLightPickCacheLimit = 16384

    /// The scene's GPU allocations, gathered once per scene: a swap needs the old
    /// and the new list, and gathering walks every draw group.
    public private(set) lazy var sceneAllocations = scene.residencyAllocations

    /// The regions the scene's `XEMI` references name, gathered once per scene.
    public private(set) lazy var emittanceRegions = scene.emittanceRegions
    /// Each region's weather `Effect Lighting` colour at this hour, set once per frame.
    public var regionEmittance: [UInt32: SIMD3<Float>] = [:]

    /// The scene's caster bounds, built once per scene for the shadow pass.
    public private(set) lazy var shadowCasters = ShadowCasterBounds(scene: scene)
    /// Each actor's own draw groups, built once per scene for its membranes.
    private(set) lazy var actorGroupsByOwner = DrawGroup.actorGroupsByOwner(in: scene)
    /// Injected framing camera — source of the sun/ambient light and the
    /// free-fly camera's starting pose. setScene may replace it.
    public var camera: SceneCamera
    /// The game state this frame draws from, replaced once per frame by `frameDriver`.
    /// A renderer without a driver keeps what its caller sets here.
    public var frameInput: RenderFrameInput
    /// Draws the dialogue camera's pivot, sightline and eye through the world-overlay
    /// registry. Off by default like every other overlay.
    public var dialogueCameraOverlayEnabled = false
    /// The input's pose maps in one, so a drawn instance costs one lookup.
    var instanceDeltas: [UInt32: float4x4] = [:]
    /// What the last adopted input held, so a change re-projects or re-merges once.
    var adoptedFOVYRadians = FirstPersonCamera.defaultFOVYRadians
    var adoptedPoseRevision = 0
    /// The weather's cloud layers; nil keeps the plain sky gradient.
    public var skyClouds: SkyClouds?
    public var cloudsEnabled = true
    /// The exposure the eye has adapted to, fed back from the GPU each frame.
    public var eyeAdaptation = EyeAdaptation()
    public let precipitation: PrecipitationVolume
    public var precipitationEnabled = true
    public var particlesEnabled = true
    public var particlesFrozen = false
    /// Blended particles and their systems draw far to near.
    public var particleSortingEnabled = true
    public var particleEmissionScale: Float = 1
    /// Placed and effect systems the last scene pass skipped as outside the view.
    public internal(set) var offscreenParticleSystemCount = 0
    /// Live grass controls. Values clamp at encode so
    /// tests/CLI callers cannot bypass renderer safety policy.
    public var grassEnabled = true
    public var grassDensityScale: Float = 1
    public var grassDrawDistance = GrassRenderPolicy.defaultDrawDistance
    public var grassWindScale: Float = 1
    /// Test/diagnostic override stays bounded by production hard cap.
    public var grassInstanceBudget = GrassRenderPolicy.maximumInstancesPerFrame
    /// World-space AI/debug overlays default off and are independently gated.
    /// Their source closures remain registered while disabled, so a toggle does
    /// not rebuild subsystem plumbing.
    public var navmeshOverlayEnabled = false
    public var pathOverlayEnabled = false
    public var detectionOverlayEnabled = false
    public let worldOverlaySources = WorldOverlaySourceRegistry()
    /// Submitted/drawn accounting from the most recently encoded overlay.
    public var lastWorldOverlayDrawStats = WorldOverlayDrawStats()
    /// Screen-space UI A/B toggle. Off -> the UI pass encodes zero draws and
    /// the frame matches a never-enabled baseline exactly.
    public var uiEnabled = true
    /// UI points -> framebuffer pixels multiplier (user preset x backing
    /// scale, supplied by the app). Clamped to UIScale.range at encode.
    public var uiScale: Float = 1
    /// The simulation side of each frame (`RenderFrameDriver.swift`). The driver
    /// owns the renderer, so the renderer holds it weakly.
    public weak var frameDriver: (any RenderFrameDriver)?
    /// UI culling/draw accounting from the most recently encoded frame.
    /// Written only by encodeUI (RendererUIPass.swift), like the other
    /// last-frame stat mirrors.
    public var lastUIDrawStats = UIDrawStats()

    public var animationTime: Float = 0
    /// Placed lights flicker and pulse as their LIGH flags ask.
    public var lightAnimationEnabled = true
    /// Actor animation switch. Off restores bind palettes;
    /// global time still advances so grass/particle effects stay independent.
    public var actorAnimationsEnabled = true
    /// The time source every frame clock reads.
    public let wallClock: any WallClock
    /// Wall-clock delta source for the animation clock, paused in menu mode.
    public var animationClock = FrameSimClock()
    public var lastAnimationUpdateMS = 0.0
    public var lastAnimationUpdatedBoneCount = 0
    /// CPU wall time of last shadow pass; idle/off frames record near-zero cost.
    public var lastShadowUpdateMS = 0.0
    /// CPU time of the last frame's shadow and scene pass encoding.
    public var lastEncodeMS = 0.0
    public let frameUniformBuffer: MTLBuffer
    /// Per-draw ring: maxFramesInFlight slots x drawUniformSlotCapacity
    /// aligned entries. Replaced (regrown) by setScene when a new scene's
    /// drawCount exceeds the capacity.
    public var drawUniformBuffer: MTLBuffer
    /// Per-frame slot count of the draw-uniform ring — power-of-two
    /// headroom over drawCount so per-cell-crossing swaps rarely realloc.
    public var drawUniformSlotCapacity: Int
    /// Per-draw nearest-light arrays, same draw-slot indexing as uniforms.
    public var pointLightBuffer: MTLBuffer
    /// Per-instance transform ring: packed `InstanceTransform` entries,
    /// `instanceSlotCapacity` per in-flight frame. Regrows like the draw-uniform ring.
    public var instanceTransformBuffer: MTLBuffer
    /// Instances per frame slot of the transform ring — power-of-two
    /// headroom over the scene's instanceCount.
    public var instanceSlotCapacity: Int
    /// Dedicated shadow-pass rings, parallel to the scene-pass rings so the two
    /// passes never collide (the scene pass resets its cursors to 0 each
    /// frame). Same sizing + regrow triggers as their scene-pass twins:
    /// shadowInstanceBuffer holds every caster once (<= instanceSlotCapacity);
    /// shadowDrawUniformBuffer holds ShadowConstantCascadeCount slots per
    /// draw-ring slot (one ShadowDrawUniforms per cascade per drawn caster).
    public var shadowInstanceBuffer: MTLBuffer
    public var shadowDrawUniformBuffer: MTLBuffer
    /// Old scene resources + rings possibly referenced by in-flight frames
    /// after a swap; strong refs held until their frames provably drain.
    public var retired: [RetiredAllocations] = []
    public let residencySet: MTLResidencySet
    public let endFrameEvent: MTLSharedEvent
    public let frameStats = FrameStats()

    public var frameIndex: Int
    public var projectionMatrix = matrix_identity_float4x4
    /// The drawable's aspect ratio, kept so the projection can be rebuilt when the camera
    /// mode or the first-person FOV changes.
    public var drawableAspectRatio: Float = 1
    /// Culling/draw counts of the last encoded frame (see SceneDrawStats).
    /// Written only by encodeScenePass (RendererScenePass.swift).
    public var lastDrawStats = SceneDrawStats()
    public var lastGrassDrawStats = GrassDrawStats()
    /// Every pipeline the renderer made, and how many came from the saved archive.
    public let pipelineCache: PipelineCache
    /// The depth target of the last scene pass, for the render-target readout.
    var lastSceneDepth: RenderTargetEntry?
    /// GPU frustum culling for the scene's static groups (RendererGPUCulling.swift).
    public var gpuCull: GPUCullState
    /// Interior room-and-portal culling (RendererRoomCulling.swift).
    public var roomCulling = RoomCullingState()
    /// Large textures keep only the levels the camera needs (TextureStreaming/).
    public var textureStreaming: TextureStreamingState
    public var rayTracedShadows: RayTracedShadowState
    /// MetalFX temporal upscaling (RendererUpscale.swift).
    public var upscale: UpscaleState
    /// Grass through object and mesh shaders (RendererMeshGrassPass.swift).
    public var meshGrass: MeshShaderGrassState
    /// Grades every frame through the copy, so a test can compare it with the tile grade.
    var imageSpaceAlwaysSplits = false
    var eyeAdaptationClock = FrameSimClock()
    /// Scene depth under the water surface (RendererWaterPass.swift).
    public var waterDepth = WaterDepthState()
    var refraction = RefractionState()
    /// Terrain bends its lighting by the TX01 normal maps of its texture sets.
    public var terrainNormalMapsEnabled = true
    /// The lit-mesh terms the frame draws; each can be turned off.
    public var shadingTerms = SurfaceShadingTerm.all
    /// The noise term undoes it; off, the LOD texture is drawn as stored.
    public var terrainLODBrightness: TerrainLODBrightness {
        guard shadingTerms.contains(.landscapeNoise) else { return .identity }
        return scene.terrainLODBrightness ?? .vanilla
    }

    /// Bound in the environment slot of a material without a cube map.
    public let blackCube: MTLTexture
    /// Set by a benchmark to get each frame's GPU time; nil in normal play.
    public var gpuFrameLog: GPUFrameLog?
    /// Set by a benchmark to time each render pass on the GPU; nil in normal play.
    public var passTimer: GPUPassTimer?
    /// The colour behind all geometry this frame (`Renderer.background(fog:drawsSky:)`).
    var sceneBackground = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    /// A Metal GPU trace of the next live frame (RendererFrameCapture.swift).
    var frameCapture = FrameCaptureState.idle
    /// A screenshot of the window frame in flight (RendererWindowCapture.swift).
    var windowCapture = WindowCaptureState.idle
    /// Shadow-pass culling/draw counts of the last encoded frame (see
    /// ShadowDrawStats). Written only by encodeShadowPass; reset to zero on
    /// idle/off frames.
    public var lastShadowDrawStats = ShadowDrawStats()

    /// `scene` nil -> synthetic DemoScene; `camera` nil -> its demo camera;
    /// `shaderLibrary` nil -> the `default.metallib` of the app or openskycli
    /// bundle. A package test passes the library its fixture loads instead.
    /// This builds the GPU half only; `GameSession(view:)` in the engine builds
    /// a renderer and drives its frames.
    public init(
        rendering view: MTKView,
        scene: RenderScene? = nil,
        camera: SceneCamera? = nil,
        shaderLibrary: MTLLibrary? = nil,
        pipelineCache: PipelineCache? = nil,
        wallClock: any WallClock = MediaWallClock()
    ) throws {
        guard let device = view.device else { throw RendererError.deviceUnavailable }
        (self.device, self.wallClock) = (device, wallClock)

        commandQueue = try GPUFactory.makeCommandQueue(device: device)
        commandBuffer = try GPUFactory.makeCommandBuffer(device: device)
        commandAllocators = try Self.makeCommandAllocators(device: device)
        argumentTable = try Self.makeArgumentTable(device: device)

        endFrameEvent = try Self.makeEndFrameEvent(device: device)
        frameIndex = GPUFactory.maxFramesInFlight
        endFrameEvent.signaledValue = UInt64(frameIndex - 1)

        Self.configure(view: view)

        let library = try shaderLibrary ?? Self.makeBundledShaderLibrary(device: device)
        let compiler = try pipelineCache ?? PipelineCache(device: device, fileURL: nil)
        self.pipelineCache = compiler
        let pipelines = try Self.makePipelines(view: view, library: library, compiler: compiler)
        (skyPipeline, cloudPipeline) = (pipelines.sky, pipelines.clouds)
        (opaquePipeline, skinnedBlendedPipelines) = (pipelines.opaque, pipelines.skinnedBlended)
        (alphaTestPipeline, blendedPipeline) = (pipelines.alphaTest, pipelines.blended)
        (skinnedOpaquePipeline, additivePipelines) = (pipelines.skinnedOpaque, pipelines.additive)
        (skinnedAlphaTestPipeline, grassPipeline) = (pipelines.skinnedAlphaTest, pipelines.grass)
        (morphedSkinnedOpaquePipeline, morphedSkinnedAlphaTestPipeline) = (
            pipelines.morphedSkinnedOpaque, pipelines.morphedSkinnedAlphaTest
        )
        (terrainPipeline, waterPipeline) = (pipelines.terrain, pipelines.water)
        (particlePipelines, debugPipelines) = (pipelines.particles, pipelines.debug)
        (materialDepthStates, waterDepthState) = try Self.makeDepthStates(device: device)
        sampler = try Self.makeSampler(device: device)
        ((shadow, uiResources), (worldOverlayResources, swf)) =
            try Self.makeAuxiliaryResources(view: view, library: library, compiler: compiler)
        ((imageSpacePass, effects), (gpuCull, upscale)) =
            try Self.makeEffectResources(view: view, library: library, compiler: compiler)
        textureStreaming = TextureStreamingState(device: device)
        rayTracedShadows = Self.makeRayTracing(library: library, compiler: compiler, view: view)
        meshGrass = MeshShaderGrassState(library: library, view: view)

        (self.scene, precipitation) = try Self.makeInitialScene(device: device, requested: scene)
        let framing = camera ?? .demo
        (self.camera, frameInput) = (framing, RenderFrameInput(view: .init(framing: framing)))
        (frameUniformBuffer, blackCube) = try Self.makeFrameResources(device: device)
        let rings = try Self.makeSceneRings(device: device, scene: self.scene)
        (drawUniformBuffer, pointLightBuffer) = (rings.drawBuffer, rings.pointLightBuffer)
        drawUniformSlotCapacity = rings.drawCapacity
        instanceTransformBuffer = rings.instanceBuffer
        instanceSlotCapacity = rings.instanceCapacity
        shadowDrawUniformBuffer = rings.shadowDrawBuffer
        shadowInstanceBuffer = rings.shadowInstanceBuffer

        residencySet = try GPUFactory.makeResidencySet(
            device: device,
            allocations: [
                frameUniformBuffer, drawUniformBuffer, pointLightBuffer,
                instanceTransformBuffer, shadowDrawUniformBuffer, shadowInstanceBuffer,
                shadow.map, uiResources.atlasTexture, uiResources.vertexBuffer,
                uiResources.uniformBuffer, worldOverlayResources.vertexBuffer,
                swf.whiteTexture, swf.fallbackRamp, imageSpacePass.uniformBuffer,
                imageSpacePass.luminanceBuffer, blackCube
            ] + effects.residentBuffers
                + self.scene.residencyAllocations + precipitation.residencyAllocations
        )
        commandQueue.addResidencySet(residencySet)

        super.init()
        // A failed save only costs the next launch a compile.
        try? compiler.saveIfNeeded()
    }
}
