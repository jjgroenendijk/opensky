// Scene-specific Metal pipeline construction split from shared renderer setup.

import Metal
import MetalKit
import OpenSkyShaderTypes

/// The render-debug pipeline set: one per geometry path. The channel is a
/// `FrameUniforms` field, so mode changes rebuild nothing. A zero alpha threshold
/// discards nothing, so the alpha-test variant also serves opaque groups.
nonisolated public struct DebugRenderPipelines: Sendable {
    public let staticMesh: MTLRenderPipelineState
    public let skinned: MTLRenderPipelineState
    public let morphedSkinned: MTLRenderPipelineState
    public let terrain: MTLRenderPipelineState
    public let grass: MTLRenderPipelineState
    public let water: MTLRenderPipelineState
}

/// One debug pipeline's recipe: the two function names, the vertex layout, and
/// whether its fragment declares the alpha-test constant. `alphaTest` is nil for
/// the fragment functions that declare no such constant (terrain, grass, water);
/// setting one there would fail specialization.
nonisolated public struct DebugPipelineRecipe {
    public let label: String
    public let vertex: String
    public let fragment: String
    public let alphaTest: Bool?
    public let layout: MTLVertexDescriptor
}

extension Renderer {
    /// A fragment function specialized on its constants. `FunctionConstantDebugView` must
    /// be defined even in shipping pipelines (Metal aborts otherwise); false folds it away.
    /// `alphaTest` is nil for terrain, grass and water, which declare no such constant.
    public static func specializedFragment(
        _ name: String,
        library: MTLLibrary,
        debugView: Bool,
        alphaTest: Bool? = nil
    ) -> MTL4SpecializedFunctionDescriptor {
        let function = MTL4LibraryFunctionDescriptor()
        function.library = library
        function.name = name
        let constants = MTLFunctionConstantValues()
        var debugEnabled = debugView
        constants.setConstantValue(
            &debugEnabled, type: .bool, index: FunctionConstantIndex.debugView.rawValue
        )
        if var alphaTest {
            constants.setConstantValue(
                &alphaTest, type: .bool, index: FunctionConstantIndex.alphaTest.rawValue
            )
        }
        let specialized = MTL4SpecializedFunctionDescriptor()
        specialized.functionDescriptor = function
        specialized.constantValues = constants
        return specialized
    }

    /// Builds the five debug pipelines. Each specializes its fragment function
    /// with `FunctionConstantDebugView` defined as true; the shipping pipelines
    /// leave it undefined, which is what keeps their compiled code unchanged.
    public static func makeDebugPipelines(
        library: MTLLibrary,
        compiler: PipelineCache,
        view: MTKView
    ) throws -> DebugRenderPipelines {
        func make(_ recipe: DebugPipelineRecipe) throws -> MTLRenderPipelineState {
            try makeDebugPipeline(
                recipe, library: library, compiler: compiler, view: view
            )
        }
        return try DebugRenderPipelines(
            staticMesh: make(DebugPipelineRecipe(
                label: "DebugStatic", vertex: "staticMeshVertex",
                fragment: "staticMeshFragment", alphaTest: true,
                layout: StaticVertexLayout.vertexDescriptor()
            )),
            skinned: make(DebugPipelineRecipe(
                label: "DebugSkinned", vertex: "skinnedMeshVertex",
                fragment: "staticMeshFragment", alphaTest: true,
                layout: SkinVertexLayout.vertexDescriptor()
            )),
            morphedSkinned: make(DebugPipelineRecipe(
                label: "DebugMorphedSkinned", vertex: "morphedSkinnedMeshVertex",
                fragment: "staticMeshFragment", alphaTest: true,
                layout: MorphVertexLayout.vertexDescriptor()
            )),
            terrain: make(DebugPipelineRecipe(
                label: "DebugTerrain", vertex: "terrainVertex",
                fragment: "terrainFragment", alphaTest: nil,
                layout: TerrainVertexLayout.vertexDescriptor()
            )),
            grass: make(DebugPipelineRecipe(
                label: "DebugGrass", vertex: "grassVertex",
                fragment: "grassFragment", alphaTest: nil,
                layout: StaticVertexLayout.vertexDescriptor()
            )),
            water: make(DebugPipelineRecipe(
                label: "DebugWater", vertex: "waterVertex",
                fragment: "waterFragment", alphaTest: nil,
                layout: StaticVertexLayout.vertexDescriptor()
            ))
        )
    }

    /// The water debug variant deliberately drops the blend state its shipping
    /// twin carries: a debug channel answers "what is here", and blending the
    /// answer with the terrain underneath would make the water plane invisible
    /// in exactly the modes meant to find it.
    private static func makeDebugPipeline(
        _ recipe: DebugPipelineRecipe,
        library: MTLLibrary,
        compiler: PipelineCache,
        view: MTKView
    ) throws -> MTLRenderPipelineState {
        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.library = library
        vertexFunction.name = recipe.vertex
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = recipe.label
        descriptor.rasterSampleCount = view.sampleCount
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = specializedFragment(
            recipe.fragment, library: library, debugView: true, alphaTest: recipe.alphaTest
        )
        descriptor.vertexDescriptor = recipe.layout
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
    }

    public static func makeGrassPipeline(
        library: MTLLibrary,
        compiler: PipelineCache,
        view: MTKView
    ) throws -> MTLRenderPipelineState {
        let vertex = MTL4LibraryFunctionDescriptor()
        vertex.library = library
        vertex.name = "grassVertex"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "GrassInstanced"
        descriptor.rasterSampleCount = view.sampleCount
        descriptor.vertexFunctionDescriptor = vertex
        descriptor.fragmentFunctionDescriptor = specializedFragment(
            "grassFragment", library: library, debugView: false
        )
        descriptor.vertexDescriptor = StaticVertexLayout.vertexDescriptor()
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
    }

    public static func makeTerrainPipeline(
        library: MTLLibrary,
        compiler: PipelineCache,
        view: MTKView
    ) throws -> MTLRenderPipelineState {
        let vertex = MTL4LibraryFunctionDescriptor()
        vertex.library = library
        vertex.name = "terrainVertex"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "TerrainSplat"
        descriptor.rasterSampleCount = view.sampleCount
        descriptor.vertexFunctionDescriptor = vertex
        descriptor.fragmentFunctionDescriptor = specializedFragment(
            "terrainFragment", library: library, debugView: false
        )
        descriptor.vertexDescriptor = TerrainVertexLayout.vertexDescriptor()
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
    }
}
