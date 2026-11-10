// Terrain, sky, and water draw items that a RenderScene carries beside its instances.

import Foundation
@preconcurrency @unsafe public import Metal
public import OpenSkyFormatsCore
public import OpenSkyRenderCore
public import OpenSkyRenderResources
import OpenSkyShaderTypes
public import simd

/// One terrain quadrant draw for the splat pipeline: quadrant mesh, its
/// per-vertex splat-weight stream (TerrainVertexLayout), the BTXT base
/// material, and the ATXT layer diffuses in blend order. Terrain always
/// draws opaque (docs/rendering/scene-drawing.md, terrain splat section).
nonisolated public struct TerrainDrawItem: Sendable {
    public let mesh: RenderMesh
    /// Two float4 weight lanes per vertex, vertex-count sized.
    public let weightsBuffer: any MTLBuffer
    /// Base diffuse + UV params; alpha fields unused (terrain is opaque).
    public let material: RenderMaterial
    /// ATXT layer diffuses, <= TerrainConstant.maxLayers, blend order.
    public let layerTextures: [any MTLTexture]
    /// TX01 normal maps of the base and of each layer, aligned with `layerTextures`.
    /// A flat placeholder stands in for a texture set without one.
    public let normals: TerrainNormalMaps
    public let modelMatrix: float4x4
    public let normalMatrix: float4x4
    /// World-space AABB for frustum culling; nil -> never culled.
    public let bounds: ModelBounds?
    /// Bit n: layer n is LTEX snow ground; `snowBaseBit`: the base is.
    public let snowLayers: UInt32

    public static let snowBaseBit = UInt32(1) << UInt32(TerrainConstant.maxLayers.rawValue)

    public init(
        mesh: RenderMesh,
        weightsBuffer: any MTLBuffer,
        material: RenderMaterial,
        layerTextures: [any MTLTexture],
        normals: TerrainNormalMaps,
        modelMatrix: float4x4,
        normalMatrix: float4x4,
        bounds: ModelBounds?,
        snowLayers: UInt32 = 0
    ) {
        self.snowLayers = snowLayers
        self.mesh = mesh
        self.weightsBuffer = weightsBuffer
        self.material = material
        self.layerTextures = layerTextures
        self.normals = normals
        self.modelMatrix = modelMatrix
        self.normalMatrix = normalMatrix
        self.bounds = bounds
    }
}

/// The normal maps of one terrain quadrant draw.
nonisolated public struct TerrainNormalMaps: Sendable {
    public let base: any MTLTexture
    public let layers: [any MTLTexture]

    public init(base: any MTLTexture, layers: [any MTLTexture]) {
        self.base = base
        self.layers = layers
    }
}

/// Exterior sky marker. Colors are procedural in the shader for now; this
/// value makes sky presence explicit per worldspace and mergeable per scene.
nonisolated public struct SkyParameters: Equatable, Sendable {
    public init() {}
}

/// One water surface: a cell plane at the CELL/WRLD water height, or a placed
/// mesh with a water shader. `look` comes from WATR.
nonisolated public struct WaterDrawItem: Sendable {
    public let mesh: RenderMesh
    public let modelMatrix: float4x4
    public let look: WaterLook
    public let bounds: ModelBounds?
    /// The cell's flow map, when the water type is flow-mapped and the file exists.
    public var flowMap: String?

    public init(mesh: RenderMesh, modelMatrix: float4x4, look: WaterLook, bounds: ModelBounds?) {
        self.mesh = mesh
        self.modelMatrix = modelMatrix
        self.look = look
        self.bounds = bounds
    }

    init(
        mesh: RenderMesh,
        modelMatrix: float4x4,
        shallowColor: SIMD3<Float>,
        deepColor: SIMD3<Float>,
        reflectionColor: SIMD3<Float>,
        bounds: ModelBounds?
    ) {
        self.init(
            mesh: mesh, modelMatrix: modelMatrix,
            look: WaterLook(
                shallowColor: shallowColor, deepColor: deepColor, reflectionColor: reflectionColor
            ),
            bounds: bounds
        )
    }
}
