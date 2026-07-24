// Metal 4 render loop; nil injected scene selects synthetic demo state for tests.

import Metal
import MetalKit
import QuartzCore
import simd

/// GPU resources retired by a scene swap, still possibly referenced by
/// frames in flight when they were retired. The strong references here keep
/// the allocations alive; residency-set removal waits until
/// `endFrameEvent.signaledValue` proves `lastFrameIndex` drained.
nonisolated private struct RetiredAllocations {
    /// Highest frame index that may still reference these allocations.
    let lastFrameIndex: UInt64
    let allocations: [MTLAllocation]
}

nonisolated enum RendererError: Error {
    case deviceUnavailable
    case commandQueueUnavailable
    case commandBufferUnavailable
    case commandAllocatorUnavailable
    case sharedEventUnavailable
    case bufferAllocationFailed
    case defaultLibraryMissing
    case pipelineAttachmentMissing
    case depthStateAllocationFailed
    case samplerAllocationFailed
    case textureAllocationFailed
    case encoderUnavailable
    case gpuTimeout
    case offscreenPumpTimedOut(maxFrames: Int)
}

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
    /// User/dev A/B toggle (the `H` key). Default on; ANDed with `shadowQuality`
    /// so it flips shadows on/off without discarding the selected quality.
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
    private(set) var scene: RenderScene
    /// Injected framing camera — source of the sun/ambient light and the
    /// free-fly camera's starting pose. setScene may replace it.
    private(set) var camera: SceneCamera
    /// Live view pose, seeded from `camera`, advanced each frame from `input`.
    var freeFlyCamera: FreeFlyCamera
    /// Fly remains default dev mode. G toggles terrain-constrained walk.
    var movementMode = CameraMovementMode.fly
    var walkController: WalkController
    /// Current resident terrain lookup, wired by GameViewController. nil in
    /// renderer-only tests/offscreen paths -> walk mode has no ground.
    var terrainSampler: WalkController.GroundSampler?
    /// Resident static collision broadphase, wired beside terrain by
    /// GameViewController. Empty in renderer-only paths.
    var collisionQuery: WalkController.CollisionQuery?
    var timeOfDay: Float
    /// Data-driven weather runtime; nil -> procedural sky + camera lighting.
    var weather: WeatherSystem?
    /// Data-driven sky/fog/light/wind + precipitation-input A/B.
    var weatherEnabled = true
    /// This frame's resolved weather (exterior only). nil -> no weather active.
    var currentResolvedWeather: ResolvedWeather?
    /// Wall-clock delta source for the weather runtime, paused in menu mode.
    var weatherClock = FrameSimClock()
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
    /// Optional main-thread per-frame hook, invoked in `draw(in:)` after the
    /// camera advances with the live free-fly position. Cell streaming drives
    /// its per-frame `update` here (and may call `setScene` back synchronously
    /// -- safe, same thread, still between frames). nil (offscreen/tests)
    /// leaves the loop unchanged.
    var onFrame: ((SIMD3<Float>) -> Void)?
    /// Wall-clock delta source for camera movement, paused in menu mode.
    var cameraClock = FrameSimClock()
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
    let frameUniformBuffer: MTLBuffer
    /// Per-draw ring: maxFramesInFlight slots x drawUniformSlotCapacity
    /// aligned entries. Replaced (regrown) by setScene when a new scene's
    /// drawCount exceeds the capacity.
    private(set) var drawUniformBuffer: MTLBuffer
    /// Per-frame slot count of the draw-uniform ring — power-of-two
    /// headroom over drawCount so per-cell-crossing swaps rarely realloc.
    private(set) var drawUniformSlotCapacity: Int
    /// Per-draw nearest-light arrays, same draw-slot indexing as uniforms.
    private(set) var pointLightBuffer: MTLBuffer
    /// Per-instance transform ring (todo 3.2 instancing): tightly packed
    /// InstanceTransform entries, instanceSlotCapacity per in-flight frame.
    /// Same regrow-on-swap treatment as the draw-uniform ring.
    private(set) var instanceTransformBuffer: MTLBuffer
    /// Instances per frame slot of the transform ring — power-of-two
    /// headroom over the scene's instanceCount.
    private(set) var instanceSlotCapacity: Int
    /// Dedicated shadow-pass rings, parallel to the scene-pass rings so the two
    /// passes never collide (the scene pass resets its cursors to 0 each
    /// frame). Same sizing + regrow triggers as their scene-pass twins:
    /// shadowInstanceBuffer holds every caster once (<= instanceSlotCapacity);
    /// shadowDrawUniformBuffer holds ShadowConstantCascadeCount slots per
    /// draw-ring slot (one ShadowDrawUniforms per cascade per drawn caster).
    private(set) var shadowInstanceBuffer: MTLBuffer
    private(set) var shadowDrawUniformBuffer: MTLBuffer
    /// Old scene resources + rings possibly referenced by in-flight frames
    /// after a swap; strong refs held until their frames provably drain.
    private var retired: [RetiredAllocations] = []
    let residencySet: MTLResidencySet
    let endFrameEvent: MTLSharedEvent
    /// Two timestamp entries (frame start/end) per in-flight slot; nil when
    /// the device cannot allocate one — stats then report CPU only.
    let timestampHeap: MTL4CounterHeap?
    let frameStats: FrameStats

    var frameIndex: Int
    var projectionMatrix = matrix_identity_float4x4
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
        timeOfDay: Float = 13
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
        shadow = try Self.makeShadowResources(device: device)
        uiResources = try Self.makeUIResources(device: device, view: view)
        swf = try Self.makeSWFPassResources(device: device, view: view)

        (self.scene, precipitation) = try Self.makeInitialScene(device: device, requested: scene)
        let resolvedCamera = camera ?? .demo
        self.camera = resolvedCamera
        freeFlyCamera = FreeFlyCamera(framing: resolvedCamera)
        walkController = WalkController(cameraPosition: freeFlyCamera.position)
        (self.timeOfDay, self.input) = (timeOfDay, input)
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
                uiResources.uniformBuffer, swf.whiteTexture, swf.fallbackRamp
            ]
                + self.scene.residencyAllocations + precipitation.residencyAllocations
        )
        commandQueue.addResidencySet(residencySet)

        timestampHeap = Self.makeTimestampHeap(device: device)
        frameStats = FrameStats(device: device)

        super.init()
    }
}

// MARK: - Scene swap (cell streaming)

extension Renderer {
    /// Replaces the drawable scene between frames; optional `camera` reseeds
    /// sun/ambient and the free-fly pose (a first real scene after an empty
    /// launch scene needs a framing pose).
    ///
    /// Threading: must run on the thread that drives draw(in:) /
    /// renderOffscreen — the main thread. The renderer has no internal locking;
    /// "between frames" is guaranteed by that shared thread. The GPU may still
    /// be executing frames that reference the OLD scene: those resources go on
    /// the retire list instead of being released here — never blocks the GPU.
    func setScene(_ newScene: RenderScene, camera newCamera: SceneCamera? = nil) throws {
        purgeRetiredResources()
        // Allocate every fallible buffer before mutating live state; a failure
        // leaves the old scene + rings intact.
        let newDraw = try regrownDrawRing(for: newScene.drawCount)
        let newInstance = try regrownInstanceRing(for: newScene.instanceCount)
        // Old scene allocations retire as a whole; anything the new scene
        // shares is filtered out at purge time (live-set check), not here.
        var retiring = scene.residencyAllocations
        scene = newScene
        if let newCamera {
            camera = newCamera
            reseedMovement(camera: newCamera)
        }
        if let newDraw {
            adoptDrawRing(newDraw, retiring: &retiring)
        }
        if let newInstance {
            adoptInstanceRing(newInstance, retiring: &retiring)
        }
        residencySet.addAllocations(newScene.residencyAllocations)
        residencySet.commit()
        // Frames < frameIndex are committed; the newest (frameIndex - 1) is the
        // last that can reference the old resources.
        retired.append(RetiredAllocations(
            lastFrameIndex: UInt64(frameIndex - 1),
            allocations: retiring
        ))
    }

    /// Replacement draw-side rings (draw + point-light + shadow-draw), sized to
    /// the new draw count. nil when the current rings already fit.
    private struct DrawRingRegrow {
        let draw: MTLBuffer
        let pointLight: MTLBuffer
        let shadowDraw: MTLBuffer
        let capacity: Int
    }

    /// Replacement instance-side rings (scene + shadow), sized to the new
    /// instance count. nil when the current rings already fit.
    private struct InstanceRingRegrow {
        let instance: MTLBuffer
        let shadowInstance: MTLBuffer
        let capacity: Int
    }

    private func regrownDrawRing(for drawCount: Int) throws -> DrawRingRegrow? {
        guard drawCount > drawUniformSlotCapacity else { return nil }
        let capacity = Self.slotCapacity(for: drawCount)
        return try DrawRingRegrow(
            draw: Self.makeUniformBuffer(
                device: device,
                length: Self.alignedDrawUniformsSize * capacity * Self.maxFramesInFlight,
                label: "DrawUniforms"
            ),
            pointLight: Self.makeUniformBuffer(
                device: device,
                length: MemoryLayout<PointLightUniform>.stride
                    * LightingConstant.maxPointLights.rawValue
                    * capacity * Self.maxFramesInFlight,
                label: "PointLights"
            ),
            shadowDraw: Self.makeUniformBuffer(
                device: device,
                length: Self.alignedDrawUniformsSize
                    * Self.shadowDrawCapacity(capacity) * Self.maxFramesInFlight,
                label: "ShadowDrawUniforms"
            ),
            capacity: capacity
        )
    }

    private func regrownInstanceRing(for instanceCount: Int) throws -> InstanceRingRegrow? {
        guard instanceCount > instanceSlotCapacity else { return nil }
        let capacity = Self.slotCapacity(for: instanceCount)
        let length = MemoryLayout<InstanceTransform>.stride * capacity * Self.maxFramesInFlight
        return try InstanceRingRegrow(
            instance: Self.makeUniformBuffer(
                device: device, length: length, label: "InstanceTransforms"
            ),
            // Per-cascade caster runs need cascadeCount x the scene ring
            // (matches makeSceneRings sizing).
            shadowInstance: Self.makeUniformBuffer(
                device: device,
                length: length * ShadowConstant.cascadeCount.rawValue,
                label: "ShadowInstanceTransforms"
            ),
            capacity: capacity
        )
    }

    /// Swaps in the new draw-side rings, retiring the old ones (they may back
    /// in-flight frames) and adding the new ones to the residency set.
    private func adoptDrawRing(_ ring: DrawRingRegrow, retiring: inout [MTLAllocation]) {
        retiring.append(drawUniformBuffer)
        retiring.append(pointLightBuffer)
        retiring.append(shadowDrawUniformBuffer)
        drawUniformBuffer = ring.draw
        pointLightBuffer = ring.pointLight
        shadowDrawUniformBuffer = ring.shadowDraw
        drawUniformSlotCapacity = ring.capacity
        residencySet.addAllocations([ring.draw, ring.pointLight, ring.shadowDraw])
    }

    private func adoptInstanceRing(_ ring: InstanceRingRegrow, retiring: inout [MTLAllocation]) {
        retiring.append(instanceTransformBuffer)
        retiring.append(shadowInstanceBuffer)
        instanceTransformBuffer = ring.instance
        shadowInstanceBuffer = ring.shadowInstance
        instanceSlotCapacity = ring.capacity
        residencySet.addAllocations([ring.instance, ring.shadowInstance])
    }

    /// Queues allocations for deferred residency-set removal once the frames
    /// that may still reference them provably drain (used by setSWFMovie;
    /// setScene manages its own retire entry alongside the ring swap).
    func retireAllocations(_ allocations: [MTLAllocation]) {
        guard !allocations.isEmpty else { return }
        retired.append(RetiredAllocations(
            lastFrameIndex: UInt64(frameIndex - 1),
            allocations: allocations
        ))
    }

    /// Drops retire-list entries whose frames provably drained
    /// (endFrameEvent.signaledValue >= tag), removing their allocations from
    /// the residency set. MTLResidencySet membership is a plain set — removals
    /// take effect at commit() even if queued frames still reference the
    /// allocation — so removal waits for the drain proof, and must skip
    /// anything the CURRENT scene or rings also use (swap A -> B -> A, or
    /// adjacent cells sharing meshes: the allocation is both retired and live).
    /// Called opportunistically from draw(in:) and setScene.
    func purgeRetiredResources() {
        guard !retired.isEmpty else { return }
        let drained = endFrameEvent.signaledValue
        var ready: [MTLAllocation] = []
        retired.removeAll { entry in
            guard entry.lastFrameIndex <= drained else { return false }
            ready.append(contentsOf: entry.allocations)
            return true
        }
        guard !ready.isEmpty else { return }
        var live = Set(scene.residencyAllocations.map(ObjectIdentifier.init))
        live.insert(ObjectIdentifier(frameUniformBuffer))
        live.insert(ObjectIdentifier(drawUniformBuffer))
        live.insert(ObjectIdentifier(pointLightBuffer))
        live.insert(ObjectIdentifier(instanceTransformBuffer))
        live.insert(ObjectIdentifier(shadowDrawUniformBuffer))
        live.insert(ObjectIdentifier(shadowInstanceBuffer))
        live.insert(ObjectIdentifier(shadow.map))
        if let movie = swf.movie {
            live.formUnion(movie.residencyAllocations.map(ObjectIdentifier.init))
        }
        // A drained A entry may share an allocation with undrained B. Keep that
        // allocation resident until every retired frame using it drains.
        for entry in retired {
            live.formUnion(entry.allocations.map(ObjectIdentifier.init))
        }
        var seen = Set<ObjectIdentifier>()
        let removable = ready.filter { allocation in
            let id = ObjectIdentifier(allocation)
            return !live.contains(id) && seen.insert(id).inserted
        }
        guard !removable.isEmpty else { return }
        residencySet.removeAllocations(removable)
        residencySet.commit()
    }
}
