// Depth-tested world-space debug-overlay pass (issue #422). Sources build a
// pure CPU primitive list each frame, one bounded buffer upload feeds the GPU,
// and triangles plus line segments share one blended pipeline.

import Metal
import MetalKit

nonisolated struct WorldOverlayDrawStats: Equatable {
    var submittedPrimitiveCount = 0
    var drawnPrimitiveCount = 0
    var triangleCount = 0
    var lineSegmentCount = 0
    var droppedPrimitiveCount = 0
    var drawCalls = 0

    var wasTruncated: Bool {
        droppedPrimitiveCount > 0
    }
}

nonisolated struct WorldOverlayResources {
    let pipeline: MTLRenderPipelineState
    let depthState: MTLDepthStencilState
    let vertexBuffer: MTLBuffer
}

extension Renderer {
    /// Hard cap across triangles and line segments. A triangle is the largest
    /// primitive at three vertices, which sizes the fixed triple-buffered ring.
    static let worldOverlayPrimitiveBudget = 65536

    static func makeWorldOverlayResources(
        device: MTLDevice,
        view: MTKView
    ) throws -> WorldOverlayResources {
        let verticesPerSlot = worldOverlayPrimitiveBudget * 3
        return try WorldOverlayResources(
            pipeline: makeWorldOverlayPipeline(device: device, view: view),
            depthState: makeWorldOverlayDepthState(device: device),
            vertexBuffer: makeUniformBuffer(
                device: device,
                length: verticesPerSlot * maxFramesInFlight * MemoryLayout<OverlayVertex>.stride,
                label: "WorldOverlayVertices"
            )
        )
    }

    private static func makeWorldOverlayPipeline(
        device: MTLDevice,
        view: MTKView
    ) throws -> MTLRenderPipelineState {
        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.defaultLibraryMissing
        }
        let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())
        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.library = library
        vertexFunction.name = "overlayVertex"
        let fragmentFunction = MTL4LibraryFunctionDescriptor()
        fragmentFunction.library = library
        fragmentFunction.name = "overlayFragment"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "WorldSpaceDebugOverlay"
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
        color.rgbBlendOperation = .add
        color.sourceAlphaBlendFactor = .one
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        color.alphaBlendOperation = .add
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Overlay geometry is occluded by the world but never modifies depth, so
    /// translucent triangles and their wire/path lines cannot hide later draws.
    private static func makeWorldOverlayDepthState(
        device: MTLDevice
    ) throws -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.label = "WorldOverlayReadOnlyDepth"
        descriptor.depthCompareFunction = .lessEqual
        descriptor.isDepthWriteEnabled = false
        guard let state = device.makeDepthStencilState(descriptor: descriptor) else {
            throw RendererError.depthStateAllocationFailed
        }
        return state
    }

    func encodeWorldOverlay(state: inout ScenePassState) {
        let context = WorldOverlayFrameContext(
            navmeshOverlayEnabled: navmeshOverlayEnabled,
            pathOverlayEnabled: pathOverlayEnabled
        )
        let list = worldOverlaySources.makeDrawList(context: context)
        let budgeted = list.budgeted(maxPrimitives: Self.worldOverlayPrimitiveBudget)
        var stats = WorldOverlayDrawStats(
            submittedPrimitiveCount: budgeted.submittedPrimitiveCount,
            drawnPrimitiveCount: budgeted.drawnPrimitiveCount,
            triangleCount: budgeted.triangleCount,
            lineSegmentCount: budgeted.lineSegmentCount,
            droppedPrimitiveCount: budgeted.droppedPrimitiveCount
        )
        defer { lastWorldOverlayDrawStats = stats }
        guard budgeted.drawnPrimitiveCount > 0 else { return }

        let vertexOffset = writeWorldOverlayVertices(budgeted.vertices, slot: state.slot)
        argumentTable.setAddress(
            worldOverlayResources.vertexBuffer.gpuAddress + UInt64(vertexOffset),
            index: BufferIndex.overlayVertices.rawValue
        )
        let encoder = state.encoder
        encoder.setRenderPipelineState(worldOverlayResources.pipeline)
        encoder.setDepthStencilState(worldOverlayResources.depthState)
        encoder.setCullMode(.none)
        if budgeted.triangleVertexCount > 0 {
            encoder.drawPrimitives(
                primitiveType: .triangle,
                vertexStart: 0,
                vertexCount: budgeted.triangleVertexCount
            )
            stats.drawCalls += 1
        }
        if budgeted.lineVertexCount > 0 {
            encoder.drawPrimitives(
                primitiveType: .line,
                vertexStart: budgeted.triangleVertexCount,
                vertexCount: budgeted.lineVertexCount
            )
            stats.drawCalls += 1
        }
    }

    private func writeWorldOverlayVertices(_ vertices: [OverlayVertex], slot: Int) -> Int {
        let stride = MemoryLayout<OverlayVertex>.stride
        let verticesPerSlot = Self.worldOverlayPrimitiveBudget * 3
        let offset = slot * verticesPerSlot * stride
        vertices.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            worldOverlayResources.vertexBuffer.contents().advanced(by: offset)
                .copyMemory(from: base, byteCount: bytes.count)
        }
        return offset
    }
}
