// Metal 4 render loop; nil injected scene selects synthetic demo state for tests.

import Metal
import MetalKit
import QuartzCore
import simd

final class Renderer: NSObject {
    /// Members below default to internal (not private) where
    /// RendererOffscreen.swift / RendererSetup.swift extend the loop
    /// cross-file; the module boundary still hides them from callers.
    nonisolated static let maxFramesInFlight = 3

    /// Uniform slots are 256-byte aligned so every ring offset satisfies
    /// Metal's buffer-offset alignment requirement. The per-draw ring is
    /// shared by static and terrain draws, so its slot fits either struct.
    static let alignedFrameUniformsSize =
        (MemoryLayout<FrameUniforms>.size + 0xFF) & -0x100
    static let alignedDrawUniformsSize =
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
    let device: MTLDevice
    let commandQueue: MTL4CommandQueue
    let commandBuffer: MTL4CommandBuffer
    let commandAllocators: [MTL4CommandAllocator]
    let argumentTable: MTL4ArgumentTable
    let skyPipeline: MTLRenderPipelineState
    let opaquePipeline: MTLRenderPipelineState
    let alphaTestPipeline: MTLRenderPipelineState
    let skinnedOpaquePipeline: MTLRenderPipelineState
    let skinnedAlphaTestPipeline: MTLRenderPipelineState
    let grassPipeline: MTLRenderPipelineState
    let terrainPipeline: MTLRenderPipelineState
    let waterPipeline: MTLRenderPipelineState
    let particlePipelines: ParticlePipelines
    let depthState: MTLDepthStencilState
    let waterDepthState: MTLDepthStencilState
    let sampler: MTLSamplerState
    /// Screen-space UI overlay (M8.1.1): pipeline (solid fills + text
    /// premultiplied over the finished 3D frame, depth-test-always, writes
    /// off), depth state, atlas sampler, r8 glyph/solid atlas texture, the
    /// triple-buffered vertex + uniform rings, and the CPU shelf-packed glyph
    /// atlas backing the texture. Encode + resolve live in RendererUIPass.swift.
    let uiResources: UIResources
    /// Depth-tested world-space debug overlay: blended pipeline, read-only
    /// depth state and fixed per-frame vertex ring (RendererOverlayPass.swift).
    let worldOverlayResources: WorldOverlayResources
    /// Atlas revision last copied into the atlas texture; re-upload on change.
    var uiUploadedAtlasRevision = -1
    /// SWF display-list layer (M8.2.4): content/mask pipelines + counting
    /// stencil states built at init; the movie package swaps via
    /// `setSWFMovie`. State accessors + encode live in RendererSWFPass.swift.
    let swf: SWFPassResources
    /// Sun-shadow pipelines + compare sampler + the shared cascade array
    /// (depth32Float, ShadowConstantCascadeCount slices). The array is created
    /// once, always resident, and bound at TextureIndexShadowMap every scene
    /// pass so validation stays clean even with shadows disabled.
    let shadow: ShadowResources
    /// A/B toggle from `World > Environment > Sun shadows`. Default on; ANDed
    /// with `shadowQuality` so it flips shadows without discarding the tier.
    var sunShadowsEnabled = true
    /// Sun-shadow quality tier (M7.1.2). `.off` skips the pass entirely; `.low`
    /// and `.high` differ in cascade count, range, and PCF taps (see the
    /// RendererShadowPass computed parameters). Set on the main thread between
    /// frames like other renderer state; the UI agent owns persistence.
    var shadowQuality = ShadowQuality.high
    /// This frame's cascades, produced by encodeShadowPass, consumed by
    /// updateFrameUniforms. Empty when shadows are off/idle this frame.
    var shadowCascades: [ShadowCascade] = []
    /// Whether encodeShadowPass rendered cascades this frame (drives the
    /// shader's shadowsEnabled flag). Reset every frame.
    var shadowsActiveThisFrame = false
    /// Meshes whose bone palette was already copied into this frame's slot —
    /// shared guard so the shadow + scene pass never double-prepare (RenderMesh
    /// palette is identical across both passes within one frame).
    var frameBonePrepared: Set<ObjectIdentifier> = []
    /// Internal, not `private(set)`: `RendererSceneSwap.swift` owns the swap
    /// cross-file (same rule as the offscreen/setup satellites above).
    var scene: RenderScene
    /// Injected framing camera — source of the sun/ambient light and the
    /// free-fly camera's starting pose. setScene may replace it.
    var camera: SceneCamera
    /// Live view pose, seeded from `camera`, advanced each frame from `input`.
    var freeFlyCamera: FreeFlyCamera
    /// Fly remains default dev mode. `G` cycles fly -> first-person walk ->
    /// third person (issue #189).
    var movementMode = CameraMovementMode.fly
    var walkController: WalkController
    /// Current resident terrain lookup, wired by GameViewController. nil in
    /// renderer-only tests/offscreen paths -> walk mode has no ground.
    var terrainSampler: WalkController.GroundSampler?
    /// Resident static collision broadphase, wired beside terrain by
    /// GameViewController. Empty in renderer-only paths.
    var collisionQuery: WalkController.CollisionQuery?
    /// Behavior-graph locomotion bridge, issue #188 (docs/engine/walk-mode.md).
    var locomotion: LocomotionBridge
    /// Orbit/shoulder framing and collision zoom for `.thirdPerson`
    /// (issue #189). Pure math over the capsule pose; holds no pose of its own.
    var thirdPersonCamera = ThirdPersonCamera()
    /// The player's rendered body, attached once the app has assembled it and
    /// deliberately not part of `scene`: it survives every cell swap
    /// (RendererPlayerBody.swift). nil in offscreen/CLI paths and until the
    /// assembly succeeds. Set through `setPlayerBody`, which also sizes the
    /// rings and manages residency; assigning it directly would draw from
    /// buffers the GPU has not been told about.
    var playerBody: PlayerBody?
    /// The player's rendered first-person arms, held for the same reason and
    /// on the same terms as `playerBody` (issue #190,
    /// RendererFirstPersonArms.swift). Set through `setPlayerFirstPersonRig`.
    var playerFirstPersonRig: PlayerFirstPersonRig?
    /// Where the simulated rigid bodies have moved since their cells were
    /// built, keyed by REFR FormID (issue #193). Published once per frame by
    /// the streaming controller's physics tick, read by the two passes that
    /// upload instance transforms. Empty in every path that runs no physics,
    /// which is what leaves those passes unchanged there.
    var dynamicInstanceDeltas: [UInt32: float4x4] = [:]
    var npcInstanceDeltas: [UInt32: float4x4] = [:]
    /// First-person field of view and the depth policy the arms are drawn
    /// under. Pure settings; holds no pose (issue #190).
    var firstPersonCamera = FirstPersonCamera()
    /// A/B toggle for the arms, so a capture can separate "the arms are wrong"
    /// from "the world behind them is wrong" (issue #190).
    var firstPersonArmsEnabled = true
    /// Game clock + its pause-aware wall-delta source + the seam TimeScale is
    /// read through (issue #164). `timeOfDay` is now a projection of this
    /// clock; see RendererGameClock.swift.
    var gameTime = RendererGameTime()
    /// Data-driven weather runtime; nil -> procedural sky + camera lighting.
    var weather: WeatherSystem?
    /// Data-driven sky/fog/light/wind + precipitation-input A/B.
    var weatherEnabled = true
    /// This frame's resolved weather (exterior only). nil -> no weather active.
    var currentResolvedWeather: ResolvedWeather?
    /// Wall-clock delta source for the weather runtime, paused in menu mode.
    var weatherClock = FrameSimClock()
    /// World audio playback graph; nil until the app wires one (offscreen and
    /// CLI paths stay silent). Ticked by RendererAudio.swift.
    var worldAudio: WorldAudioEngine?
    /// Music director (M9.2.3), ticked from the same paused-aware audio hook so
    /// a playlist advance freezes with the world sim. nil until audio is on.
    var musicDirector: WorldMusicDirector?
    /// Footstep director (issue #352), fed from the same paused-aware audio
    /// hook: it drains the locomotion bridge's fired graph events, so a paused
    /// frame — which plans no step and fires nothing — leaves the queue alone.
    /// nil until audio is on.
    var footstepDirector: WorldAudioFootstepDirector?
    /// Wall-clock delta source for the audio tick, paused in menu mode.
    var audioClock = FrameSimClock()
    let precipitation: PrecipitationVolume
    var precipitationEnabled = true
    var particlesEnabled = true
    var particlesFrozen = false
    var particleEmissionScale: Float = 1
    /// World > Environment > Grass live controls. Values clamp at encode so
    /// tests/CLI callers cannot bypass renderer safety policy.
    var grassEnabled = true
    var grassDensityScale: Float = 1
    var grassDrawDistance = GrassRenderPolicy.defaultDrawDistance
    var grassWindScale: Float = 1
    /// Test/diagnostic override stays bounded by production hard cap.
    var grassInstanceBudget = GrassRenderPolicy.maximumInstancesPerFrame
    /// World-space AI/debug overlays default off and are independently gated.
    /// Their source closures remain registered while disabled, so a toggle does
    /// not rebuild subsystem plumbing.
    var navmeshOverlayEnabled = false
    var pathOverlayEnabled = false
    var detectionOverlayEnabled = false
    let worldOverlaySources = WorldOverlaySourceRegistry()
    /// Submitted/drawn accounting from the most recently encoded overlay.
    var lastWorldOverlayDrawStats = WorldOverlayDrawStats()
    /// Screen-space UI A/B toggle. Off -> the UI pass encodes zero draws and
    /// the frame matches a never-enabled baseline exactly.
    var uiEnabled = true
    /// Resolved to a draw list each frame against the framebuffer pixel size +
    /// uiScale. Default empty -> zero draws.
    var uiScene = UIScene.empty
    /// UI points -> framebuffer pixels multiplier (user preset x backing
    /// scale, supplied by the app). Clamped to UIScale.range at encode.
    var uiScale: Float = 1
    /// Menu-mode world-sim pause gate (todo 8.1.2). True freezes the per-frame
    /// time advance (game time, camera, animations, weather, particles,
    /// precipitation) while the frame still renders and the screen-space UI
    /// still draws. Driven by MenuModeController.isWorldSimPaused; the frame
    /// clocks keep their marks fresh while paused so resume carries no time jump.
    var worldSimPaused = false
    /// UI culling/draw accounting from the most recently encoded frame.
    /// Written only by encodeUI (RendererUIPass.swift), like the other
    /// last-frame stat mirrors.
    var lastUIDrawStats = UIDrawStats()

    /// Free-fly input, drained once per `draw(in:)`; nil (offscreen/tests) ->
    /// the camera stays on its seeded pose.
    let input: CameraInputState?
    /// Main-thread per-frame hook, invoked in `draw(in:)` after the camera
    /// advances with the live free-fly position. Cell streaming drives its
    /// per-frame `update` here (and may call `setScene` back synchronously
    /// -- safe, same thread, still between frames), and the HUD refreshes
    /// beside it. No handlers (offscreen/tests) leaves the loop unchanged.
    let onFrame = CallbackFanOut<SIMD3<Float>>()
    /// World simulation tick, invoked once per drawn frame after the game clock
    /// advances. The delta is seconds, already gated by the renderer's own
    /// `FrameSimClock`, so a paused frame delivers zero.
    var onWorldUpdate: ((Float) -> Void)?
    /// CPU wall time of the world-simulation callback, which currently owns
    /// the per-frame Papyrus VM advance. Exactly zero when no callback is set.
    var lastScriptUpdateMS = 0.0
    /// Wall-clock delta source for the world simulation tick (the Papyrus VM),
    /// paused in menu mode.
    var worldSimClock = FrameSimClock()
    /// Wall-clock delta source for camera movement, paused in menu mode.
    var cameraClock = FrameSimClock()
    /// The delta `advanceCamera` last ran with, clamped exactly as the walk
    /// controller clamps it. The dynamic-body world steps on the same clock as
    /// the player capsule (issue #193), and reading the value the capsule
    /// actually used is what keeps the two from drifting apart in menu mode or
    /// after a stall.
    /// Set by `advanceCamera` in the RendererMovement satellite, which is why
    /// it is not `private(set)`.
    var lastCameraDelta: Float = 0
    var animationTime: Float = 0
    /// World > Environment actor-animation A/B. Off restores bind palettes;
    /// global time still advances so grass/particle effects stay independent.
    var actorAnimationsEnabled = true
    /// Wall-clock delta source for the animation clock, paused in menu mode.
    var animationClock = FrameSimClock()
    var lastAnimationUpdateMS = 0.0
    var lastAnimationUpdatedBoneCount = 0
    /// CPU wall time of last shadow pass; idle/off frames record near-zero cost.
    var lastShadowUpdateMS = 0.0
    /// CPU wall time of the last per-frame audio update (listener pose + engine
    /// tick + music director). Exactly zero on a frame that did no audio work,
    /// which is every frame while no `WorldAudioEngine` is attached.
    var lastAudioUpdateMS = 0.0
    let frameUniformBuffer: MTLBuffer
    /// Per-draw ring: maxFramesInFlight slots x drawUniformSlotCapacity
    /// aligned entries. Replaced (regrown) by setScene when a new scene's
    /// drawCount exceeds the capacity.
    var drawUniformBuffer: MTLBuffer
    /// Per-frame slot count of the draw-uniform ring — power-of-two
    /// headroom over drawCount so per-cell-crossing swaps rarely realloc.
    var drawUniformSlotCapacity: Int
    /// Per-draw nearest-light arrays, same draw-slot indexing as uniforms.
    var pointLightBuffer: MTLBuffer
    /// Per-instance transform ring (todo 3.2 instancing): tightly packed
    /// InstanceTransform entries, instanceSlotCapacity per in-flight frame.
    /// Same regrow-on-swap treatment as the draw-uniform ring.
    var instanceTransformBuffer: MTLBuffer
    /// Instances per frame slot of the transform ring — power-of-two
    /// headroom over the scene's instanceCount.
    var instanceSlotCapacity: Int
    /// Dedicated shadow-pass rings, parallel to the scene-pass rings so the two
    /// passes never collide (the scene pass resets its cursors to 0 each
    /// frame). Same sizing + regrow triggers as their scene-pass twins:
    /// shadowInstanceBuffer holds every caster once (<= instanceSlotCapacity);
    /// shadowDrawUniformBuffer holds ShadowConstantCascadeCount slots per
    /// draw-ring slot (one ShadowDrawUniforms per cascade per drawn caster).
    var shadowInstanceBuffer: MTLBuffer
    var shadowDrawUniformBuffer: MTLBuffer
    /// Old scene resources + rings possibly referenced by in-flight frames
    /// after a swap; strong refs held until their frames provably drain.
    var retired: [RetiredAllocations] = []
    let residencySet: MTLResidencySet
    let endFrameEvent: MTLSharedEvent
    /// Two timestamp entries (frame start/end) per in-flight slot; nil when
    /// the device cannot allocate one — stats then report CPU only.
    let timestampHeap: MTL4CounterHeap?
    let frameStats: FrameStats

    var frameIndex: Int
    var projectionMatrix = matrix_identity_float4x4
    /// The drawable's aspect ratio, kept so the projection can be rebuilt
    /// without waiting for the next resize. Camera mode and the first-person
    /// field of view both change it mid-session (issue #190).
    var drawableAspectRatio: Float = 1
    /// Culling/draw counts of the last encoded frame (see SceneDrawStats).
    /// Written only by encodeScenePass (RendererScenePass.swift).
    var lastDrawStats = SceneDrawStats()
    var lastGrassDrawStats = GrassDrawStats()
    /// Shadow-pass culling/draw counts of the last encoded frame (see
    /// ShadowDrawStats). Written only by encodeShadowPass; reset to zero on
    /// idle/off frames.
    var lastShadowDrawStats = ShadowDrawStats()

    /// `scene` nil -> synthetic DemoScene; `camera` nil -> its demo camera;
    /// `input` nil -> static seeded pose (offscreen/tests). The app passes a
    /// built cell scene + `SceneCamera.framing(bounds:)` + a shared
    /// `CameraInputState` for free-fly (todo 2.8).
    init(
        view: MTKView,
        scene: RenderScene? = nil,
        camera: SceneCamera? = nil,
        input: CameraInputState? = nil,
        timeOfDay: Float = 13,
        movementConfiguration: PlayerMovementConfiguration = .synthetic
    ) throws {
        guard let device = view.device else { throw RendererError.deviceUnavailable }
        self.device = device

        guard let queue = device.makeMTL4CommandQueue() else {
            throw RendererError.commandQueueUnavailable
        }
        commandQueue = queue

        guard let buffer = device.makeCommandBuffer() else {
            throw RendererError.commandBufferUnavailable
        }
        commandBuffer = buffer

        commandAllocators = try Self.makeCommandAllocators(device: device)

        argumentTable = try Self.makeArgumentTable(device: device)

        guard let event = device.makeSharedEvent() else {
            throw RendererError.sharedEventUnavailable
        }
        endFrameEvent = event
        frameIndex = Self.maxFramesInFlight
        endFrameEvent.signaledValue = UInt64(frameIndex - 1)

        Self.configure(view: view)

        let pipelines = try Self.makePipelines(device: device, view: view)
        (skyPipeline, opaquePipeline) = (pipelines.sky, pipelines.opaque)
        (alphaTestPipeline, skinnedOpaquePipeline) = (pipelines.alphaTest, pipelines.skinnedOpaque)
        (skinnedAlphaTestPipeline, grassPipeline) = (pipelines.skinnedAlphaTest, pipelines.grass)
        (terrainPipeline, waterPipeline) = (pipelines.terrain, pipelines.water)
        particlePipelines = pipelines.particles
        depthState = try Self.makeDepthState(device: device)
        waterDepthState = try Self.makeWaterDepthState(device: device)
        sampler = try Self.makeSampler(device: device)
        ((shadow, uiResources), (worldOverlayResources, swf)) =
            try Self.makeAuxiliaryResources(device: device, view: view)

        (self.scene, precipitation) = try Self.makeInitialScene(device: device, requested: scene)
        let resolvedCamera = camera ?? .demo
        self.camera = resolvedCamera
        freeFlyCamera = FreeFlyCamera(framing: resolvedCamera)
        (walkController, locomotion) = Self.makeMovement(freeFlyCamera, movementConfiguration)
        (gameTime, self.input) = (RendererGameTime(clock: GameClock(hour: timeOfDay)), input)
        frameUniformBuffer = try Self.makeFrameUniformBuffer(device: device)
        let rings = try Self.makeSceneRings(device: device, scene: self.scene)
        drawUniformBuffer = rings.drawBuffer
        pointLightBuffer = rings.pointLightBuffer
        drawUniformSlotCapacity = rings.drawCapacity
        instanceTransformBuffer = rings.instanceBuffer
        instanceSlotCapacity = rings.instanceCapacity
        shadowDrawUniformBuffer = rings.shadowDrawBuffer
        shadowInstanceBuffer = rings.shadowInstanceBuffer

        residencySet = try Self.makeResidencySet(
            device: device,
            allocations: [
                frameUniformBuffer, drawUniformBuffer, pointLightBuffer,
                instanceTransformBuffer, shadowDrawUniformBuffer, shadowInstanceBuffer,
                shadow.map, uiResources.atlasTexture, uiResources.vertexBuffer,
                uiResources.uniformBuffer, worldOverlayResources.vertexBuffer,
                swf.whiteTexture, swf.fallbackRamp
            ]
                + self.scene.residencyAllocations + precipitation.residencyAllocations
        )
        commandQueue.addResidencySet(residencySet)

        timestampHeap = Self.makeTimestampHeap(device: device)
        frameStats = FrameStats(device: device)

        super.init()
    }
}
