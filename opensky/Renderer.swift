// Metal 4 static-mesh render loop (todo 2.6): opaque + alpha-test pipeline
// variants, per-frame and per-draw uniform rings, textures + sampler bound
// through the MTL4ArgumentTable, GPU frame timing via counter-heap
// timestamps. Command flow adapted from Apple's Xcode Metal 4 game template.
// Scene content is the synthetic DemoScene until cell scene build (todo
// 2.7) feeds real world geometry through the same path.

import Metal
import MetalKit
import simd

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
    private static let maxFramesInFlight = 3

    /// Uniform slots are 256-byte aligned so every ring offset satisfies
    /// Metal's buffer-offset alignment requirement.
    private static let alignedFrameUniformsSize =
        (MemoryLayout<FrameUniforms>.size + 0xFF) & -0x100
    private static let alignedDrawUniformsSize =
        (MemoryLayout<DrawUniforms>.size + 0xFF) & -0x100

    /// Near/far at Skyrim scale per docs/decisions/coordinates.md: near 10
    /// units (~14 cm; below ~1 unit destroys depth precision), far 16 cells.
    private static let nearPlane: Float = 10
    private static let farPlane: Float = 65536

    private let device: MTLDevice
    private let commandQueue: MTL4CommandQueue
    private let commandBuffer: MTL4CommandBuffer
    private let commandAllocators: [MTL4CommandAllocator]
    private let argumentTable: MTL4ArgumentTable
    private let opaquePipeline: MTLRenderPipelineState
    private let alphaTestPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let sampler: MTLSamplerState
    private let scene: RenderScene
    private let frameUniformBuffer: MTLBuffer
    /// Per-draw ring: maxFramesInFlight slots x scene.drawCount aligned
    /// entries. The scene is fixed for 2.6; cell streaming (2.7+) grows it.
    private let drawUniformBuffer: MTLBuffer
    private let residencySet: MTLResidencySet
    private let endFrameEvent: MTLSharedEvent
    /// Two timestamp entries (frame start/end) per in-flight slot; nil when
    /// the device cannot allocate one — stats then report CPU only.
    private let timestampHeap: MTL4CounterHeap?
    private let frameStats: FrameStats

    private var frameIndex: Int
    private var projectionMatrix = matrix_identity_float4x4

    init(view: MTKView) throws {
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

        let tableDescriptor = MTL4ArgumentTableDescriptor()
        tableDescriptor.maxBufferBindCount = 3
        tableDescriptor.maxTextureBindCount = 1
        tableDescriptor.maxSamplerStateBindCount = 1
        argumentTable = try device.makeArgumentTable(descriptor: tableDescriptor)

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
        depthState = try Self.makeDepthState(device: device)
        sampler = try Self.makeSampler(device: device)

        scene = try DemoScene.build(device: device)
        frameUniformBuffer = try Self.makeUniformBuffer(
            device: device,
            length: Self.alignedFrameUniformsSize * Self.maxFramesInFlight,
            label: "FrameUniforms"
        )
        drawUniformBuffer = try Self.makeUniformBuffer(
            device: device,
            length: Self.alignedDrawUniformsSize
                * max(scene.drawCount, 1) * Self.maxFramesInFlight,
            label: "DrawUniforms"
        )

        residencySet = try Self.makeResidencySet(
            device: device,
            allocations: [frameUniformBuffer, drawUniformBuffer] + scene.residencyAllocations
        )
        commandQueue.addResidencySet(residencySet)

        let heapDescriptor = MTL4CounterHeapDescriptor()
        heapDescriptor.type = .timestamp
        heapDescriptor.count = 2 * Self.maxFramesInFlight
        timestampHeap = try? device.makeCounterHeap(descriptor: heapDescriptor)
        frameStats = FrameStats(device: device)

        super.init()
    }

    // MARK: - Per-frame uniforms

    /// Writes this frame's uniforms into its 256-byte-aligned slot and
    /// returns the byte offset of that slot. Camera + sun come from the
    /// demo scene; the free-fly camera (todo 2.8) replaces the former.
    private func updateFrameUniforms(slot: Int, projection: float4x4) -> Int {
        let offset = Self.alignedFrameUniformsSize * slot
        let viewMatrix = MatrixMath.lookAt(
            eye: DemoScene.cameraEye,
            target: DemoScene.cameraTarget,
            up: SIMD3<Float>(0, 0, 1)
        )
        var uniforms = FrameUniforms(
            viewProjectionMatrix: projection * viewMatrix,
            cameraPosition: DemoScene.cameraEye,
            sunDirection: DemoScene.sunDirection,
            sunColor: DemoScene.sunColor,
            ambientColor: DemoScene.ambientColor
        )
        frameUniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<FrameUniforms>.size)
        return offset
    }

    /// Writes one draw's uniforms into the ring and returns its byte offset.
    private func updateDrawUniforms(slot: Int, draw: Int, item: DrawItem) -> Int {
        let offset = Self.alignedDrawUniformsSize * (slot * scene.drawCount + draw)
        var uniforms = DrawUniforms(
            modelMatrix: item.modelMatrix,
            normalMatrix: item.normalMatrix,
            uvOffset: item.material.uvOffset,
            uvScale: item.material.uvScale,
            materialAlpha: item.material.alpha,
            alphaThreshold: item.material.alphaTestThreshold ?? 0
        )
        drawUniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<DrawUniforms>.size)
        return offset
    }

    // MARK: - Draw

    private func encode(
        items: [DrawItem],
        pipeline: MTLRenderPipelineState,
        encoder: MTL4RenderCommandEncoder,
        slot: Int,
        drawOffset: Int
    ) {
        guard !items.isEmpty else { return }
        encoder.setRenderPipelineState(pipeline)
        for (index, item) in items.enumerated() {
            let uniformOffset = updateDrawUniforms(
                slot: slot,
                draw: drawOffset + index,
                item: item
            )
            argumentTable.setAddress(
                item.mesh.vertexBuffer.gpuAddress,
                index: BufferIndex.vertices.rawValue
            )
            argumentTable.setAddress(
                drawUniformBuffer.gpuAddress + UInt64(uniformOffset),
                index: BufferIndex.drawUniforms.rawValue
            )
            argumentTable.setTexture(
                item.material.diffuse.gpuResourceID,
                index: TextureIndex.diffuse.rawValue
            )
            encoder.setCullMode(item.material.doubleSided ? .none : .back)
            encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: item.mesh.indexCount,
                indexType: .uint16,
                indexBuffer: item.mesh.indexBuffer.gpuAddress,
                indexBufferLength: item.mesh.indexBuffer.length
            )
        }
    }

    /// Encodes the whole scene as one render pass into the open command
    /// buffer. Returns false when the encoder cannot be created.
    private func encodeScenePass(
        descriptor: MTL4RenderPassDescriptor,
        slot: Int,
        projection: float4x4
    ) -> Bool {
        let frameOffset = updateFrameUniforms(slot: slot, projection: projection)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return false }
        encoder.label = "Static Mesh Encoder"
        encoder.setDepthStencilState(depthState)
        // Winding per docs/decisions/coordinates.md (verified on the demo
        // scene ground plane): faces authored counter-clockwise seen from
        // outside are front under our view/projection.
        encoder.setFrontFacing(.counterClockwise)
        encoder.setArgumentTable(argumentTable, stages: [.vertex, .fragment])
        argumentTable.setAddress(
            frameUniformBuffer.gpuAddress + UInt64(frameOffset),
            index: BufferIndex.frameUniforms.rawValue
        )
        argumentTable.setSamplerState(
            sampler.gpuResourceID,
            index: SamplerIndex.trilinear.rawValue
        )
        encode(
            items: scene.opaque,
            pipeline: opaquePipeline,
            encoder: encoder,
            slot: slot,
            drawOffset: 0
        )
        encode(
            items: scene.alphaTested,
            pipeline: alphaTestPipeline,
            encoder: encoder,
            slot: slot,
            drawOffset: scene.opaque.count
        )
        encoder.endEncoding()
        return true
    }

    /// Resolves the timestamp pair the slot's previous frame wrote; safe
    /// because the shared-event wait guarantees that frame finished.
    private func resolveTimestamps(slot: Int) -> (start: UInt64, end: UInt64)? {
        guard
            let heap = timestampHeap,
            frameIndex >= 2 * Self.maxFramesInFlight,
            let data = try? heap.resolveCounterRange(slot * 2 ..< slot * 2 + 2),
            data.count >= 2 * MemoryLayout<MTL4TimestampHeapEntry>.stride
        else { return nil }
        let entries = data.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: MTL4TimestampHeapEntry.self))
        }
        return (entries[0].timestamp, entries[1].timestamp)
    }
}

// MARK: - Offscreen render

extension Renderer {
    /// Color (shared, CPU-readable) + depth (private) render targets for
    /// one offscreen frame.
    private func makeOffscreenTargets(
        width: Int,
        height: Int
    ) throws -> (color: MTLTexture, depth: MTLTexture) {
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: width,
            height: height,
            mipmapped: false
        )
        colorDescriptor.usage = .renderTarget
        colorDescriptor.storageMode = .shared // CPU readback
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        depthDescriptor.usage = .renderTarget
        depthDescriptor.storageMode = .private
        guard
            let color = device.makeTexture(descriptor: colorDescriptor),
            let depth = device.makeTexture(descriptor: depthDescriptor)
        else { throw RendererError.textureAllocationFailed }
        color.label = "OffscreenColor"
        depth.label = "OffscreenDepth"
        return (color, depth)
    }

    /// Renders one frame into an offscreen texture and blocks until the GPU
    /// finishes it — deterministic render tests and engine-output
    /// screenshots (todo 2.9) without drawable/compositor involvement.
    func renderOffscreen(width: Int, height: Int) throws -> MTLTexture {
        let (color, depth) = try makeOffscreenTargets(width: width, height: height)

        residencySet.addAllocations([color, depth])
        residencySet.commit()
        defer {
            residencySet.removeAllocations([color, depth])
            residencySet.commit()
        }

        let descriptor = MTL4RenderPassDescriptor()
        descriptor.colorAttachments[0].texture = color
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0, green: 0, blue: 0, alpha: 1
        )
        descriptor.depthAttachment.texture = depth
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.storeAction = .dontCare
        descriptor.depthAttachment.clearDepth = 1

        // Drain every in-flight frame, then run one frame synchronously
        // through the normal slot/event bookkeeping.
        endFrameEvent.wait(untilSignaledValue: UInt64(frameIndex - 1), timeoutMS: 2000)
        let slot = frameIndex % Self.maxFramesInFlight
        let allocator = commandAllocators[slot]
        allocator.reset()
        commandBuffer.beginCommandBuffer(allocator: allocator)
        let projection = MatrixMath.perspective(
            fovYRadians: MatrixMath.radians(fromDegrees: 65),
            aspectRatio: Float(width) / Float(height),
            nearZ: Self.nearPlane,
            farZ: Self.farPlane
        )
        let encoded = encodeScenePass(descriptor: descriptor, slot: slot, projection: projection)
        commandBuffer.endCommandBuffer()
        guard encoded else { throw RendererError.encoderUnavailable }

        commandQueue.commit([commandBuffer])
        commandQueue.signalEvent(endFrameEvent, value: UInt64(frameIndex))
        let finished = endFrameEvent.wait(
            untilSignaledValue: UInt64(frameIndex),
            timeoutMS: 5000
        )
        frameIndex += 1
        guard finished else { throw RendererError.gpuTimeout }
        return color
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
