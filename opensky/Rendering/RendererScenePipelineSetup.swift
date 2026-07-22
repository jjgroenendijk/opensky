// Scene-specific Metal pipeline construction split from shared renderer setup.

import Metal
import MetalKit

extension Renderer {
    static func makeGrassPipeline(
        library: MTLLibrary,
        compiler: MTL4Compiler,
        view: MTKView
    ) throws -> MTLRenderPipelineState {
        let vertex = MTL4LibraryFunctionDescriptor()
        vertex.library = library
        vertex.name = "grassVertex"
        let fragment = MTL4LibraryFunctionDescriptor()
        fragment.library = library
        fragment.name = "grassFragment"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "GrassInstanced"
        descriptor.rasterSampleCount = view.sampleCount
        descriptor.vertexFunctionDescriptor = vertex
        descriptor.fragmentFunctionDescriptor = fragment
        descriptor.vertexDescriptor = StaticVertexLayout.vertexDescriptor()
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
    }

    static func makeTerrainPipeline(
        library: MTLLibrary,
        compiler: MTL4Compiler,
        view: MTKView
    ) throws -> MTLRenderPipelineState {
        let vertex = MTL4LibraryFunctionDescriptor()
        vertex.library = library
        vertex.name = "terrainVertex"
        let fragment = MTL4LibraryFunctionDescriptor()
        fragment.library = library
        fragment.name = "terrainFragment"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "TerrainSplat"
        descriptor.rasterSampleCount = view.sampleCount
        descriptor.vertexFunctionDescriptor = vertex
        descriptor.fragmentFunctionDescriptor = fragment
        descriptor.vertexDescriptor = TerrainVertexLayout.vertexDescriptor()
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
    }
}
