// Metal 4 static-mesh render loop (todo 2.6): opaque + alpha-test pipeline
// variants, per-frame and per-draw uniform rings, textures + sampler bound
// through the MTL4ArgumentTable, GPU frame timing via counter-heap
// timestamps. Command flow adapted from Apple's Xcode Metal 4 game template.
// Scene + camera are injected at init (todo 2.7 app wiring): the app hands a
// built cell scene with a framing SceneCamera; nil falls back to the
// synthetic DemoScene + its demo camera (tests, missing game data).

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

/// Per-frame culling + draw accounting from the most recently encoded
/// frame — deterministic evidence for culling tests and streaming triage.
nonisolated struct SceneDrawStats: Equatable {
    /// drawIndexedPrimitives calls encoded.
    var drawCalls = 0
    /// Items drawn after frustum culling (static + terrain).
    var drawnInstances = 0
    /// Items the frustum test skipped this frame.
    var culledInstances = 0
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
    static let maxFramesInFlight = 3

    /// Uniform slots are 256-byte aligned so every ring offset satisfies
    /// Metal's buffer-offset alignment requirement. The per-draw ring is
    /// shared by static and terrain draws, so its slot fits either struct.
    static let alignedFrameUniformsSize =
        (MemoryLayout<FrameUniforms>.size + 0xFF) & -0x100
    static let alignedDrawUniformsSize =
        (max(
            MemoryLayout<DrawUniforms>.size,
            MemoryLayout<TerrainDrawUniforms>.size,
            MemoryLayout<WaterDrawUniforms>.size
        )
            + 0xFF) & -0x100

    /// Near/far at Skyrim scale per docs/decisions/coordinates.md: near 10
    /// units (~14 cm; below ~1 unit destroys depth precision), far 16 cells.
    static let nearPlane: Float = 10
    static let farPlane: Float = 65536

    let device: MTLDevice
    let commandQueue: MTL4CommandQueue
    let commandBuffer: MTL4CommandBuffer
    let commandAllocators: [MTL4CommandAllocator]
    let argumentTable: MTL4ArgumentTable
    let skyPipeline: MTLRenderPipelineState
    let opaquePipeline: MTLRenderPipelineState
    let alphaTestPipeline: MTLRenderPipelineState
    let terrainPipeline: MTLRenderPipelineState
    let waterPipeline: MTLRenderPipelineState
    let depthState: MTLDepthStencilState
    let waterDepthState: MTLDepthStencilState
    let sampler: MTLSamplerState
    /// Current drawable scene; swapped between frames via setScene.
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
    /// Procedural exterior sky clock. May change between frames.
    var timeOfDay: Float
    /// Free-fly input, drained once per `draw(in:)`; nil (offscreen/tests) ->
    /// the camera stays on its seeded pose.
    let input: CameraInputState?
    /// Optional main-thread per-frame hook, invoked in `draw(in:)` after the
    /// camera advances with the live free-fly position. Cell streaming drives
    /// its per-frame `update` here (and may call `setScene` back synchronously
    /// -- safe, same thread, still between frames). nil (offscreen/tests)
    /// leaves the loop unchanged.
    var onFrame: ((SIMD3<Float>) -> Void)?
    /// CACurrentMediaTime of the previous `draw(in:)`, for real delta time.
    var lastUpdateTime: CFTimeInterval?
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

        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = 1

        let pipelines = try Self.makePipelines(device: device, view: view)
        skyPipeline = pipelines.sky
        opaquePipeline = pipelines.opaque
        alphaTestPipeline = pipelines.alphaTest
        terrainPipeline = pipelines.terrain
        waterPipeline = pipelines.water
        depthState = try Self.makeDepthState(device: device)
        waterDepthState = try Self.makeWaterDepthState(device: device)
        sampler = try Self.makeSampler(device: device)

        self.scene = try scene ?? DemoScene.build(device: device)
        let resolvedCamera = camera ?? .demo
        self.camera = resolvedCamera
        freeFlyCamera = FreeFlyCamera(framing: resolvedCamera)
        walkController = WalkController(cameraPosition: freeFlyCamera.position)
        self.timeOfDay = timeOfDay
        self.input = input
        frameUniformBuffer = try Self.makeUniformBuffer(
            device: device,
            length: Self.alignedFrameUniformsSize * Self.maxFramesInFlight,
            label: "FrameUniforms"
        )
        let rings = try Self.makeSceneRings(device: device, scene: self.scene)
        drawUniformBuffer = rings.drawBuffer
        pointLightBuffer = rings.pointLightBuffer
        drawUniformSlotCapacity = rings.drawCapacity
        instanceTransformBuffer = rings.instanceBuffer
        instanceSlotCapacity = rings.instanceCapacity

        residencySet = try Self.makeResidencySet(
            device: device,
            allocations: [
                frameUniformBuffer, drawUniformBuffer, pointLightBuffer,
                instanceTransformBuffer
            ]
                + self.scene.residencyAllocations
        )
        commandQueue.addResidencySet(residencySet)

        timestampHeap = Self.makeTimestampHeap(device: device)
        frameStats = FrameStats(device: device)

        super.init()
    }

    /// Two timestamp entries (frame start/end) per in-flight slot; nil when the
    /// device cannot allocate one — stats then report CPU time only.
    private static func makeTimestampHeap(device: MTLDevice) -> MTL4CounterHeap? {
        let heapDescriptor = MTL4CounterHeapDescriptor()
        heapDescriptor.type = .timestamp
        heapDescriptor.count = 2 * maxFramesInFlight
        return try? device.makeCounterHeap(descriptor: heapDescriptor)
    }

    /// Ring slots per frame for `count` draws: next power of two, min 1 —
    /// headroom so the per-cell-crossing swaps of streaming rarely realloc.
    static func slotCapacity(for count: Int) -> Int {
        count <= 1 ? 1 : 1 << (Int.bitWidth - (count - 1).leadingZeroBitCount)
    }

    /// Scene-sized GPU rings: per-group uniform ring + per-instance
    /// transform ring, both with slotCapacity headroom.
    struct SceneRings {
        let drawBuffer: MTLBuffer
        let pointLightBuffer: MTLBuffer
        let drawCapacity: Int
        let instanceBuffer: MTLBuffer
        let instanceCapacity: Int
    }

    /// Allocates both rings for a scene — shared by init and the regrow
    /// path in setScene (identical sizing policy in one place).
    static func makeSceneRings(device: MTLDevice, scene: RenderScene) throws -> SceneRings {
        let drawCapacity = slotCapacity(for: scene.drawCount)
        let instanceCapacity = slotCapacity(for: scene.instanceCount)
        return try SceneRings(
            drawBuffer: makeUniformBuffer(
                device: device,
                length: alignedDrawUniformsSize * drawCapacity * maxFramesInFlight,
                label: "DrawUniforms"
            ),
            pointLightBuffer: makeUniformBuffer(
                device: device,
                length: MemoryLayout<PointLightUniform>.stride
                    * LightingConstant.maxPointLights.rawValue
                    * drawCapacity * maxFramesInFlight,
                label: "PointLights"
            ),
            drawCapacity: drawCapacity,
            instanceBuffer: makeUniformBuffer(
                device: device,
                length: MemoryLayout<InstanceTransform>.stride
                    * instanceCapacity * maxFramesInFlight,
                label: "InstanceTransforms"
            ),
            instanceCapacity: instanceCapacity
        )
    }

    // MARK: - Scene swap (cell streaming)

    /// Replaces the drawable scene between frames; optional `camera`
    /// reseeds sun/ambient and the free-fly pose (a first real scene after
    /// an empty launch scene needs a framing pose).
    ///
    /// Threading: must run on the thread that drives draw(in:) /
    /// renderOffscreen — the main thread. The renderer has no internal
    /// locking; "between frames" is guaranteed by that shared thread. The
    /// GPU may still be executing frames that reference the OLD scene:
    /// those resources go on the retire list instead of being released or
    /// evicted here — this method never blocks on the GPU.
    func setScene(_ newScene: RenderScene, camera newCamera: SceneCamera? = nil) throws {
        purgeRetiredResources()
        // Prepare every fallible allocation before mutating live renderer
        // state. Allocation failure leaves old scene + rings intact.
        var nextDrawBuffer = drawUniformBuffer
        var nextPointLightBuffer = pointLightBuffer
        var nextDrawCapacity = drawUniformSlotCapacity
        if newScene.drawCount > drawUniformSlotCapacity {
            nextDrawCapacity = Self.slotCapacity(for: newScene.drawCount)
            nextDrawBuffer = try Self.makeUniformBuffer(
                device: device,
                length: Self.alignedDrawUniformsSize
                    * nextDrawCapacity * Self.maxFramesInFlight,
                label: "DrawUniforms"
            )
            nextPointLightBuffer = try Self.makeUniformBuffer(
                device: device,
                length: MemoryLayout<PointLightUniform>.stride
                    * LightingConstant.maxPointLights.rawValue
                    * nextDrawCapacity * Self.maxFramesInFlight,
                label: "PointLights"
            )
        }
        var nextInstanceBuffer = instanceTransformBuffer
        var nextInstanceCapacity = instanceSlotCapacity
        if newScene.instanceCount > instanceSlotCapacity {
            nextInstanceCapacity = Self.slotCapacity(for: newScene.instanceCount)
            nextInstanceBuffer = try Self.makeUniformBuffer(
                device: device,
                length: MemoryLayout<InstanceTransform>.stride
                    * nextInstanceCapacity * Self.maxFramesInFlight,
                label: "InstanceTransforms"
            )
        }

        // Old scene allocations retire as a whole; anything the new scene
        // shares with it is filtered out at purge time (live-set check in
        // purgeRetiredResources), not here — simpler and equally correct.
        var retiring = scene.residencyAllocations
        scene = newScene
        if let newCamera {
            camera = newCamera
            freeFlyCamera = FreeFlyCamera(framing: newCamera)
            walkController.reset(cameraPosition: freeFlyCamera.position)
        }
        if nextDrawBuffer !== drawUniformBuffer {
            // Old ring may back in-flight frames — retire, never reuse.
            retiring.append(drawUniformBuffer)
            retiring.append(pointLightBuffer)
            drawUniformBuffer = nextDrawBuffer
            pointLightBuffer = nextPointLightBuffer
            drawUniformSlotCapacity = nextDrawCapacity
            residencySet.addAllocations([nextDrawBuffer, nextPointLightBuffer])
        }
        if nextInstanceBuffer !== instanceTransformBuffer {
            retiring.append(instanceTransformBuffer)
            instanceTransformBuffer = nextInstanceBuffer
            instanceSlotCapacity = nextInstanceCapacity
            residencySet.addAllocations([nextInstanceBuffer])
        }
        residencySet.addAllocations(newScene.residencyAllocations)
        residencySet.commit()
        // Frames < frameIndex are committed; the newest (frameIndex - 1) is
        // the last that can reference the old resources.
        retired.append(RetiredAllocations(
            lastFrameIndex: UInt64(frameIndex - 1),
            allocations: retiring
        ))
    }

    /// Drops retire-list entries whose frames provably drained
    /// (endFrameEvent.signaledValue >= tag), removing their allocations
    /// from the residency set. MTLResidencySet membership is a plain set —
    /// no reference counting, and removals take effect at commit() even if
    /// queued frames still reference the allocation — so removal must wait
    /// for the drain proof, and must skip anything the CURRENT scene or
    /// rings also use (swap A -> B -> A, or adjacent cells sharing
    /// meshes/textures: the shared allocation is both retired and live).
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
        // A drained A entry may share an allocation with undrained B. Keep
        // that allocation resident until every retired frame using it drains.
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

// MARK: - GPU timestamps

/// Encode path lives in Rendering/RendererScenePass.swift (file-length
/// limits); this extension keeps the counter-heap timestamp reads next to
/// the draw loop that consumes them.
extension Renderer {
    /// Reads a slot's timestamp pair straight from the counter heap. Only
    /// valid when the caller proved (shared-event wait) that the frame which
    /// wrote the slot finished.
    func readTimestampPair(slot: Int) -> (start: UInt64, end: UInt64)? {
        guard
            let heap = timestampHeap,
            let data = try? heap.resolveCounterRange(slot * 2 ..< slot * 2 + 2),
            data.count >= 2 * MemoryLayout<MTL4TimestampHeapEntry>.stride
        else { return nil }
        let entries = data.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: MTL4TimestampHeapEntry.self))
        }
        return (entries[0].timestamp, entries[1].timestamp)
    }

    /// Resolves the timestamp pair the slot's previous frame wrote; safe
    /// because the shared-event wait guarantees that frame finished. The
    /// depth guard skips the first ring lap, before any slot was written.
    func resolveTimestamps(slot: Int) -> (start: UInt64, end: UInt64)? {
        guard frameIndex >= 2 * Self.maxFramesInFlight else { return nil }
        return readTimestampPair(slot: slot)
    }
}
