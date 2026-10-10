// Terrain, sky, and water draw items that a RenderScene carries beside its instances.

import Foundation
@preconcurrency import Metal
import OpenSkyFormatsCore
import OpenSkyShaderTypes
import simd

/// One terrain quadrant draw for the splat pipeline: quadrant mesh, its
/// per-vertex splat-weight stream (TerrainVertexLayout), the BTXT base
/// material, and the ATXT layer diffuses in blend order. Terrain always
/// draws opaque (docs/rendering/scene-drawing.md, terrain splat section).
nonisolated public struct TerrainDrawItem: Sendable {
    public let mesh: RenderMesh
    /// Two float4 weight lanes per vertex, vertex-count sized.
    public let weightsBuffer: MTLBuffer
    /// Base diffuse + UV params; alpha fields unused (terrain is opaque).
    public let material: RenderMaterial
    /// ATXT layer diffuses, <= TerrainConstant.maxLayers, blend order.
    public let layerTextures: [MTLTexture]
    /// TX01 normal maps of the base and of each layer, aligned with `layerTextures`.
    /// A flat placeholder stands in for a texture set without one.
    public let normals: TerrainNormalMaps
    public let modelMatrix: float4x4
    public let normalMatrix: float4x4
    /// World-space AABB for frustum culling; nil -> never culled.
    public let bounds: ModelBounds?

    public init(
        mesh: RenderMesh,
        weightsBuffer: MTLBuffer,
        material: RenderMaterial,
        layerTextures: [MTLTexture],
        normals: TerrainNormalMaps,
        modelMatrix: float4x4,
        normalMatrix: float4x4,
        bounds: ModelBounds?
    ) {
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
    public let base: MTLTexture
    public let layers: [MTLTexture]
    /// Base and layer maps that came from a TX01 path, for the panel readout.
    public let resolvedCount: Int

    public init(base: MTLTexture, layers: [MTLTexture], resolvedCount: Int) {
        self.base = base
        self.layers = layers
        self.resolvedCount = resolvedCount
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

    public init(mesh: RenderMesh, modelMatrix: float4x4, look: WaterLook, bounds: ModelBounds?) {
        self.mesh = mesh
        self.modelMatrix = modelMatrix
        self.look = look
        self.bounds = bounds
    }

    public init(
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
