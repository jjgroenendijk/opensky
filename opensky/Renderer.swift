// Metal 4 render loop. Draws a placeholder rotating triangle to prove the
// full pipeline (device, shader compiler, argument tables, residency sets,
// frame pacing) end to end before real world geometry arrives.
// Command flow adapted from Apple's Xcode Metal 4 game template.

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
}

final class Renderer: NSObject {
    private static let maxFramesInFlight = 3

    /// Uniform slots are 256-byte aligned so each frame's slice satisfies
    /// Metal's buffer-offset alignment requirement.
    private static let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100

    private static let triangleVertices = [
        TriangleVertex(position: SIMD3<Float>(0, 0.75, 0), color: SIMD4<Float>(1, 0, 0, 1)),
        TriangleVertex(position: SIMD3<Float>(-0.75, -0.75, 0), color: SIMD4<Float>(0, 1, 0, 1)),
        TriangleVertex(position: SIMD3<Float>(0.75, -0.75, 0), color: SIMD4<Float>(0, 0, 1, 1))
    ]

    private let device: MTLDevice
    private let commandQueue: MTL4CommandQueue
    private let commandBuffer: MTL4CommandBuffer
    private let commandAllocators: [MTL4CommandAllocator]
    private let argumentTable: MTL4ArgumentTable
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let vertexBuffer: MTLBuffer
    private let uniformBuffer: MTLBuffer
    private let residencySet: MTLResidencySet
    private let endFrameEvent: MTLSharedEvent

    private var frameIndex: Int
    private var projectionMatrix = matrix_identity_float4x4
    private var rotation: Float = 0

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
        tableDescriptor.maxBufferBindCount = 2
        argumentTable = try device.makeArgumentTable(descriptor: tableDescriptor)

        guard let event = device.makeSharedEvent() else {
            throw RendererError.sharedEventUnavailable
        }
        endFrameEvent = event
        frameIndex = Self.maxFramesInFlight
        endFrameEvent.signaledValue = UInt64(frameIndex - 1)

        vertexBuffer = try Self.makeVertexBuffer(device: device)
        uniformBuffer = try Self.makeUniformBuffer(device: device)

        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = 1
        pipelineState = try Self.makePipelineState(device: device, view: view)
        depthState = try Self.makeDepthState(device: device)

        residencySet = try Self.makeResidencySet(
            device: device,
            buffers: [vertexBuffer, uniformBuffer]
        )
        commandQueue.addResidencySet(residencySet)

        super.init()
    }

    private static func makeVertexBuffer(device: MTLDevice) throws -> MTLBuffer {
        let length = MemoryLayout<TriangleVertex>.stride * triangleVertices.count
        guard
            let buffer = device.makeBuffer(
                bytes: triangleVertices,
                length: length,
                options: .storageModeShared
            ) else { throw RendererError.bufferAllocationFailed }
        buffer.label = "TriangleVertices"
        return buffer
    }

    private static func makeUniformBuffer(device: MTLDevice) throws -> MTLBuffer {
        guard
            let buffer = device.makeBuffer(
                length: alignedUniformsSize * maxFramesInFlight,
                options: .storageModeShared
            ) else { throw RendererError.bufferAllocationFailed }
        buffer.label = "Uniforms"
        return buffer
    }

    private static func makeVertexDescriptor() -> MTLVertexDescriptor {
        let position = VertexAttribute.position.rawValue
        let color = VertexAttribute.color.rawValue
        let vertices = BufferIndex.vertices.rawValue

        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[position].format = .float3
        descriptor.attributes[position].offset = 0
        descriptor.attributes[position].bufferIndex = vertices
        descriptor.attributes[color].format = .float4
        descriptor.attributes[color].offset = 16 // after 16-byte aligned float3, see ShaderTypes.h
        descriptor.attributes[color].bufferIndex = vertices
        descriptor.layouts[vertices].stride = MemoryLayout<TriangleVertex>.stride
        descriptor.layouts[vertices].stepRate = 1
        descriptor.layouts[vertices].stepFunction = .perVertex
        return descriptor
    }

    private static func makePipelineState(
        device: MTLDevice,
        view: MTKView
    ) throws -> MTLRenderPipelineState {
        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.defaultLibraryMissing
        }
        let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())

        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.library = library
        vertexFunction.name = "vertexShader"
        let fragmentFunction = MTL4LibraryFunctionDescriptor()
        fragmentFunction.library = library
        fragmentFunction.name = "fragmentShader"

        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "OpenSky Render Pipeline"
        descriptor.rasterSampleCount = view.sampleCount
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = fragmentFunction
        descriptor.vertexDescriptor = makeVertexDescriptor()
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Standard opaque depth: write-through, closer fragment wins. Metal 4
    /// binds depth attachment format at pass time (MTKView `depth32Float`),
    /// not in the pipeline descriptor.
    private static func makeDepthState(device: MTLDevice) throws -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.label = "OpaqueDepth"
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true
        guard let state = device.makeDepthStencilState(descriptor: descriptor) else {
            throw RendererError.depthStateAllocationFailed
        }
        return state
    }

    private static func makeResidencySet(
        device: MTLDevice,
        buffers: [MTLBuffer]
    ) throws -> MTLResidencySet {
        let descriptor = MTLResidencySetDescriptor()
        descriptor.initialCapacity = buffers.count
        let residencySet = try device.makeResidencySet(descriptor: descriptor)
        residencySet.addAllocations(buffers)
        residencySet.commit()
        return residencySet
    }

    /// Writes this frame's uniforms into its 256-byte-aligned slot and
    /// returns the byte offset of that slot.
    private func updateUniforms(slot: Int) -> Int {
        let offset = Self.alignedUniformsSize * slot
        rotation += 0.01
        let model = MatrixMath.rotation(radians: rotation, axis: SIMD3<Float>(0, 0, 1))
        let viewMatrix = MatrixMath.translation(SIMD3<Float>(0, 0, -2))
        var uniforms = Uniforms(
            projectionMatrix: projectionMatrix,
            modelViewMatrix: simd_mul(viewMatrix, model)
        )
        uniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<Uniforms>.size)
        return offset
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_: MTKView, drawableSizeWillChange size: CGSize) {
        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = MatrixMath.perspective(
            fovYRadians: MatrixMath.radians(fromDegrees: 65),
            aspectRatio: aspect,
            nearZ: 0.1,
            farZ: 100
        )
    }

    func draw(in view: MTKView) {
        guard
            let drawable = view.currentDrawable,
            let passDescriptor = view.currentMTL4RenderPassDescriptor,
            let metalLayer = view.layer as? CAMetalLayer
        else { return }

        // Block until the GPU finishes the frame that used this slot.
        endFrameEvent.wait(
            untilSignaledValue: UInt64(frameIndex - Self.maxFramesInFlight),
            timeoutMS: 10
        )

        let slot = frameIndex % Self.maxFramesInFlight
        let allocator = commandAllocators[slot]
        allocator.reset()
        commandBuffer.beginCommandBuffer(allocator: allocator)

        let uniformOffset = updateUniforms(slot: slot)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return }
        encoder.label = "Primary Render Encoder"
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        // Winding + cull per docs/decisions/coordinates.md: NIF content is
        // D3D-authored, front faces stay clockwise in Metal window coords.
        encoder.setFrontFacing(.clockwise)
        encoder.setCullMode(.back)
        encoder.setArgumentTable(argumentTable, stages: [.vertex])
        argumentTable.setAddress(vertexBuffer.gpuAddress, index: BufferIndex.vertices.rawValue)
        argumentTable.setAddress(
            uniformBuffer.gpuAddress + UInt64(uniformOffset),
            index: BufferIndex.uniforms.rawValue
        )
        encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.useResidencySet(metalLayer.residencySet)
        commandBuffer.endCommandBuffer()

        commandQueue.waitForDrawable(drawable)
        commandQueue.commit([commandBuffer])
        commandQueue.signalDrawable(drawable)
        commandQueue.signalEvent(endFrameEvent, value: UInt64(frameIndex))
        frameIndex += 1
        drawable.present()
    }
}
