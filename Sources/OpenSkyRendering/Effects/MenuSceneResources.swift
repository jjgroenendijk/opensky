// The menu scene's pipelines, uniform ring, and the scene a menu set this frame.
// See docs/rendering/menu-scene.md.

@preconcurrency import Metal
import MetalKit
import OpenSkyShaderTypes

public final class MenuSceneResources {
    /// At most this many shapes draw in one frame; the rest are dropped.
    public static let drawLimit = 4096
    static let uniformStride = (MemoryLayout<MenuSceneUniforms>.size + 0xFF) & -0x100

    /// Set each frame by the open menu; nil draws nothing.
    public internal(set) var scene: MenuScene?
    /// Shapes the last frame drew, for the readout.
    public internal(set) var lastDraws = 0
    /// Buffers and textures added to the residency set, by object.
    var resident: [ObjectIdentifier: MTLAllocation] = [:]

    let pipelines: ParticlePipelines
    let depthState: MTLDepthStencilState
    /// Tests and writes depth, for a scene drawn in front of the world.
    let frontDepthState: MTLDepthStencilState
    let uniformBuffer: MTLBuffer

    init(device: MTLDevice, library: MTLLibrary, view: MTKView, compiler: PipelineCache) throws {
        pipelines = try Renderer.makeBlendPipelines(
            Renderer.BlendPipelineNames(
                vertex: "menuSceneVertex", fragment: "menuSceneFragment", label: "MenuScene"
            ),
            library: library, compiler: compiler, view: view
        )
        let depth = MTLDepthStencilDescriptor()
        depth.label = "MenuSceneDepth"
        depth.depthCompareFunction = .always
        depth.isDepthWriteEnabled = false
        guard let state = device.makeDepthStencilState(descriptor: depth) else {
            throw RendererError.depthStateAllocationFailed
        }
        depthState = state
        let front = MTLDepthStencilDescriptor()
        front.label = "MenuSceneFrontDepth"
        front.depthCompareFunction = .less
        front.isDepthWriteEnabled = true
        guard let frontState = device.makeDepthStencilState(descriptor: front) else {
            throw RendererError.depthStateAllocationFailed
        }
        frontDepthState = frontState
        guard
            let buffer = device.makeBuffer(
                length: Self.uniformStride * Self.drawLimit * Renderer.maxFramesInFlight,
                options: .storageModeShared
            )
        else { throw RendererError.bufferAllocationFailed }
        buffer.label = "MenuSceneUniforms"
        uniformBuffer = buffer
    }
}
