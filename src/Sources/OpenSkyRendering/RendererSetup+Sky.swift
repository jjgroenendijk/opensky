// Pipelines for the sky objects: the star and aurora meshes and the sun, glare,
// and moon cards. One premultiplied blend serves both additive and covering objects.

public import Metal
import MetalKit
import OpenSkyRenderResources

nonisolated public struct SkyObjectPipelines: Sendable {
    public let mesh: any MTLRenderPipelineState
    public let card: any MTLRenderPipelineState
}

nonisolated public struct SkyLayerPipelines: Sendable {
    public let clouds: any MTLRenderPipelineState
    public let objects: SkyObjectPipelines
}

extension Renderer {
    static func makeSkyObjectPipelines(
        library: any MTLLibrary,
        compiler: PipelineCache,
        view: MTKView
    ) throws -> SkyObjectPipelines {
        func make(vertex: String, label: String) throws -> any MTLRenderPipelineState {
            let vertexFunction = MTL4LibraryFunctionDescriptor()
            vertexFunction.library = library
            vertexFunction.name = vertex
            let fragmentFunction = MTL4LibraryFunctionDescriptor()
            fragmentFunction.library = library
            fragmentFunction.name = "skyObjectFragment"
            let descriptor = MTL4RenderPipelineDescriptor()
            descriptor.label = label
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
            color.sourceAlphaBlendFactor = .one
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try compiler.makeRenderPipelineState(descriptor: descriptor)
        }
        return try SkyObjectPipelines(
            mesh: make(vertex: "skyMeshVertex", label: "SkyMeshes"),
            card: make(vertex: "skyCardVertex", label: "SkyCards")
        )
    }
}
