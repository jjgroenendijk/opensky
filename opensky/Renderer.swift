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
    case depthStateAllocationFailed
    case samplerAllocationFailed
    case textureAllocationFailed
    case encoderUnavailable
    case gpuTimeout
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
        (max(MemoryLayout<DrawUniforms>.size, MemoryLayout<TerrainDrawUniforms>.size)
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
    let opaquePipeline: MTLRenderPipelineState
    let alphaTestPipeline: MTLRenderPipelineState
    let terrainPipeline: MTLRenderPipelineState
    let depthState: MTLDepthStencilState
    let sampler: MTLSamplerState
    let scene: RenderScene
    /// Injected framing camera — source of the sun/ambient light and the
    /// free-fly camera's starting pose.
    let camera: SceneCamera
    /// Live view pose, seeded from `camera`, advanced each frame from `input`.
    var freeFlyCamera: FreeFlyCamera
    /// Free-fly input, drained once per `draw(in:)`; nil (offscreen/tests) ->
    /// the camera stays on its seeded pose.
    private let input: CameraInputState?
    /// CACurrentMediaTime of the previous `draw(in:)`, for real delta time.
    private var lastUpdateTime: CFTimeInterval?
    let frameUniformBuffer: MTLBuffer
    /// Per-draw ring: maxFramesInFlight slots x scene.drawCount aligned
    /// entries. The scene is fixed for 2.6; cell streaming (2.7+) grows it.
    let drawUniformBuffer: MTLBuffer
    let residencySet: MTLResidencySet
    let endFrameEvent: MTLSharedEvent
    /// Two timestamp entries (frame start/end) per in-flight slot; nil when
    /// the device cannot allocate one — stats then report CPU only.
    let timestampHeap: MTL4CounterHeap?
    let frameStats: FrameStats

    var frameIndex: Int
    private var projectionMatrix = matrix_identity_float4x4
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
        input: CameraInputState? = nil
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

        commandAllocators = try (0 ..< Self.maxFramesInFlight).map { _ in
            guard let allocator = device.makeCommandAllocator() else {
                throw RendererError.commandAllocatorUnavailable
            }
            return allocator
        }

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
        opaquePipeline = pipelines.opaque
        alphaTestPipeline = pipelines.alphaTest
        terrainPipeline = pipelines.terrain
        depthState = try Self.makeDepthState(device: device)
        sampler = try Self.makeSampler(device: device)

        self.scene = try scene ?? DemoScene.build(device: device)
        let resolvedCamera = camera ?? .demo
        self.camera = resolvedCamera
        freeFlyCamera = FreeFlyCamera(framing: resolvedCamera)
        self.input = input
        frameUniformBuffer = try Self.makeUniformBuffer(
            device: device,
            length: Self.alignedFrameUniformsSize * Self.maxFramesInFlight,
            label: "FrameUniforms"
        )
        drawUniformBuffer = try Self.makeUniformBuffer(
            device: device,
            length: Self.alignedDrawUniformsSize
                * max(self.scene.drawCount, 1) * Self.maxFramesInFlight,
            label: "DrawUniforms"
        )

        residencySet = try Self.makeResidencySet(
            device: device,
            allocations: [frameUniformBuffer, drawUniformBuffer]
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

    // MARK: - Camera

    /// Advances the free-fly camera by one frame of input using real elapsed
    /// time. First frame (or no input) makes no move. dt is clamped so a stall
    /// (breakpoint, window occluded) cannot teleport the camera.
    private func advanceCamera() {
        guard let input else { return }
        let now = CACurrentMediaTime()
        let dt = lastUpdateTime.map { Float(min(now - $0, 0.1)) } ?? 0
        lastUpdateTime = now
        freeFlyCamera.update(input.makeInput(dt: dt))
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
    private func resolveTimestamps(slot: Int) -> (start: UInt64, end: UInt64)? {
        guard frameIndex >= 2 * Self.maxFramesInFlight else { return nil }
        return readTimestampPair(slot: slot)
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_: MTKView, drawableSizeWillChange size: CGSize) {
        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = MatrixMath.perspective(
            fovYRadians: MatrixMath.radians(fromDegrees: 65),
            aspectRatio: aspect,
            nearZ: Self.nearPlane,
            farZ: Self.farPlane
        )
    }

    func draw(in view: MTKView) {
        guard
            let drawable = view.currentDrawable,
            let passDescriptor = view.currentMTL4RenderPassDescriptor,
            let metalLayer = view.layer as? CAMetalLayer
        else { return }

        let cpuStart = frameStats.beginFrame()

        advanceCamera()

        // Block until the GPU finishes the frame that used this slot.
        endFrameEvent.wait(
            untilSignaledValue: UInt64(frameIndex - Self.maxFramesInFlight),
            timeoutMS: 10
        )

        let slot = frameIndex % Self.maxFramesInFlight
        let gpuTicks = resolveTimestamps(slot: slot)
        let allocator = commandAllocators[slot]
        allocator.reset()
        commandBuffer.beginCommandBuffer(allocator: allocator)
        if let heap = timestampHeap {
            commandBuffer.writeTimestamp(counterHeap: heap, index: slot * 2)
        }

        let encoded = encodeScenePass(
            descriptor: passDescriptor,
            slot: slot,
            projection: projectionMatrix
        )
        guard encoded else {
            commandBuffer.endCommandBuffer()
            return
        }

        if let heap = timestampHeap {
            commandBuffer.writeTimestamp(counterHeap: heap, index: slot * 2 + 1)
        }
        commandBuffer.useResidencySet(metalLayer.residencySet)
        commandBuffer.endCommandBuffer()

        commandQueue.waitForDrawable(drawable)
        commandQueue.commit([commandBuffer])
        commandQueue.signalDrawable(drawable)
        commandQueue.signalEvent(endFrameEvent, value: UInt64(frameIndex))
        frameIndex += 1
        drawable.present()

        frameStats.endFrame(cpuStartNS: cpuStart, gpuTicks: gpuTicks)
    }
}
