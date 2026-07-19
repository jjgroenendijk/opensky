// Drawable scene for the static-mesh pipeline (todo 2.6): engine Models ->
// GPU meshes + resolved textures -> flat draw lists with precomputed
// per-draw matrices, opaque items grouped before alpha-tested ones so the
// renderer switches pipeline once. Texture lookup is a caller-supplied
// closure — the demo scene feeds procedural textures, cell scene build
// (todo 2.7) will feed VFS + TextureLoader, this type stays agnostic.

import Foundation
import Metal
import simd

/// Resolves a material's texture key to a ready MTLTexture. `key` nil means
/// the material has no texture — implementations return a placeholder.
typealias TextureProvider = (_ key: String?, _ usage: TextureUsage) -> MTLTexture

/// GPU-side material: resolved diffuse texture + the scalar parameters the
/// shader consumes. Static NIF alpha blending remains deferred; milestone
/// 3.5 water uses its dedicated blend pipeline instead.
nonisolated struct RenderMaterial {
    let diffuse: MTLTexture
    let uvOffset: SIMD2<Float>
    let uvScale: SIMD2<Float>
    let alpha: Float
    /// nil -> opaque pipeline; set -> alpha-test pipeline variant.
    let alphaTestThreshold: Float?
    /// Render both faces (cull mode none for this draw).
    let doubleSided: Bool

    init(material: Material, textureProvider: TextureProvider) {
        diffuse = textureProvider(material.diffuseTexture, .color)
        uvOffset = material.uvOffset
        uvScale = material.uvScale
        alpha = material.alpha
        alphaTestThreshold = material.alphaTestThreshold
        doubleSided = material.doubleSided
    }
}

/// One engine Model uploaded: GPU meshes + resolved materials, shareable
/// across many instances (todo 2.7 mesh library keys these by VFS path).
nonisolated final class RenderModel {
    let meshes: [RenderMesh]
    let materials: [RenderMaterial]

    init(device: MTLDevice, model: Model, textureProvider: TextureProvider) throws {
        meshes = try model.meshes.map { try RenderMesh(device: device, mesh: $0) }
        materials = model.materials.map {
            RenderMaterial(material: $0, textureProvider: textureProvider)
        }
    }
}

/// One placed model going into a RenderScene: instance transform plus the
/// world-space AABB used for frustum culling (model bounds pushed through
/// the transform). nil bounds -> the instance is never culled.
nonisolated struct RenderPlacement {
    let model: RenderModel
    let transform: float4x4
    let bounds: ModelBounds?

    init(model: RenderModel, transform: float4x4, bounds: ModelBounds? = nil) {
        self.model = model
        self.transform = transform
        self.bounds = bounds
    }
}

/// One instance within a DrawGroup: world-space matrices + culling AABB.
nonisolated struct DrawInstance {
    let modelMatrix: float4x4
    /// Inverse-transpose of modelMatrix (world-space normals).
    let normalMatrix: float4x4
    /// World-space AABB for frustum culling. Model-level bounds pushed
    /// through the instance transform — shared by every mesh of the
    /// instance, so conservative per mesh. nil -> never culled.
    let bounds: ModelBounds?
}

/// One instanced draw call (todo 3.2): every instance shares the mesh +
/// material, drawn as a single drawIndexedPrimitives with instanceCount.
/// Grouping key is (mesh identity, diffuse identity): a RenderMesh belongs
/// to exactly one RenderModel whose materials array pins one material per
/// slot, so identical meshes imply identical material scalars — the diffuse
/// ObjectIdentifier rides along defensively.
nonisolated struct DrawGroup {
    let mesh: RenderMesh
    let material: RenderMaterial
    /// Mutable only during scene construction (GroupAccumulator).
    fileprivate(set) var instances: [DrawInstance]
}

/// Ordered mesh+material grouping: first appearance fixes group order so
/// composed scenes stay deterministic across recompositions.
nonisolated private struct GroupAccumulator {
    private struct Key: Hashable {
        let mesh: ObjectIdentifier
        let diffuse: ObjectIdentifier
    }

    private var indexByKey: [Key: Int] = [:]
    private(set) var groups: [DrawGroup] = []

    mutating func add(mesh: RenderMesh, material: RenderMaterial, instance: DrawInstance) {
        let key = Key(mesh: ObjectIdentifier(mesh), diffuse: ObjectIdentifier(material.diffuse))
        if let index = indexByKey[key] {
            groups[index].instances.append(instance)
        } else {
            indexByKey[key] = groups.count
            groups.append(DrawGroup(mesh: mesh, material: material, instances: [instance]))
        }
    }

    mutating func add(group: DrawGroup) {
        for instance in group.instances {
            add(mesh: group.mesh, material: group.material, instance: instance)
        }
    }
}

/// One terrain quadrant draw for the splat pipeline: quadrant mesh, its
/// per-vertex splat-weight stream (TerrainVertexLayout), the BTXT base
/// material, and the ATXT layer diffuses in blend order. Terrain always
/// draws opaque (docs/rendering/metal4-renderer.md, terrain splat section).
nonisolated struct TerrainDrawItem {
    let mesh: RenderMesh
    /// Two float4 weight lanes per vertex, vertex-count sized.
    let weightsBuffer: MTLBuffer
    /// Base diffuse + UV params; alpha fields unused (terrain is opaque).
    let material: RenderMaterial
    /// ATXT layer diffuses, <= TerrainConstant.maxLayers, blend order.
    let layerTextures: [MTLTexture]
    let modelMatrix: float4x4
    let normalMatrix: float4x4
    /// World-space AABB for frustum culling; nil -> never culled.
    let bounds: ModelBounds?
}

/// Exterior sky marker. Colors are procedural in the shader for now; this
/// value makes sky presence explicit per worldspace and mergeable per scene.
nonisolated struct SkyParameters: Equatable {}

/// One exterior-cell water plane. Geometry is a reusable 4096-unit quad;
/// modelMatrix places it at CELL/WRLD water height. Colors come from WATR.
nonisolated struct WaterDrawItem {
    let mesh: RenderMesh
    let modelMatrix: float4x4
    let shallowColor: SIMD3<Float>
    let deepColor: SIMD3<Float>
    let reflectionColor: SIMD3<Float>
    let bounds: ModelBounds?
}

/// Draw lists for one frame's scene. Each placement's meshes become
/// DrawInstances (modelMatrix = instance * meshLocal) grouped by mesh +
/// material into instanced DrawGroups (todo 3.2), opaque groups before
/// alpha-tested ones. Terrain items carry their own layer
/// textures + weight streams and draw through the terrain splat pipeline,
/// one non-instanced draw each.
nonisolated struct RenderScene {
    let opaque: [DrawGroup]
    let alphaTested: [DrawGroup]
    let terrain: [TerrainDrawItem]
    let water: [WaterDrawItem]
    let sky: SkyParameters?
    let lighting: RenderLighting?
    let pointLights: [RenderPointLight]

    init(
        instances: [RenderPlacement],
        terrain: [TerrainDrawItem] = [],
        water: [WaterDrawItem] = [],
        sky: SkyParameters? = nil,
        lighting: RenderLighting? = nil,
        pointLights: [RenderPointLight] = []
    ) {
        var opaque = GroupAccumulator()
        var alphaTested = GroupAccumulator()
        for placement in instances {
            let model = placement.model
            for mesh in model.meshes {
                // Slot validated against the producing Model by RenderModel
                // construction order; guard anyway — external data upstream.
                guard mesh.materialSlot < model.materials.count else { continue }
                let material = model.materials[mesh.materialSlot]
                let modelMatrix = placement.transform * mesh.localTransform
                let instance = DrawInstance(
                    modelMatrix: modelMatrix,
                    normalMatrix: MatrixMath.normalMatrix(modelMatrix),
                    bounds: placement.bounds
                )
                if material.alphaTestThreshold == nil {
                    opaque.add(mesh: mesh, material: material, instance: instance)
                } else {
                    alphaTested.add(mesh: mesh, material: material, instance: instance)
                }
            }
        }
        self.opaque = opaque.groups
        self.alphaTested = alphaTested.groups
        self.terrain = terrain
        self.water = water
        self.sky = sky
        self.lighting = lighting
        self.pointLights = pointLights
    }

    /// Merges already-built scenes into one draw-list union — grid/streaming
    /// composition (CellSceneComposition). Each source scene already carries
    /// absolute world-space matrices from its own cell build, so merging
    /// needs no re-transform. Groups with the same mesh + material fold
    /// together (adjacent cells placing the same model share one instanced
    /// draw); `residencyAllocations` still dedups across the merged lists.
    init(merging scenes: [RenderScene]) {
        var opaque = GroupAccumulator()
        var alphaTested = GroupAccumulator()
        for scene in scenes {
            for group in scene.opaque {
                opaque.add(group: group)
            }
            for group in scene.alphaTested {
                alphaTested.add(group: group)
            }
        }
        self.opaque = opaque.groups
        self.alphaTested = alphaTested.groups
        terrain = scenes.flatMap(\.terrain)
        water = scenes.flatMap(\.water)
        sky = scenes.lazy.compactMap(\.sky).first
        lighting = scenes.lazy.compactMap(\.lighting).first
        pointLights = scenes.flatMap(\.pointLights)
    }

    /// CPU light culling: stable distance order, original scene order as
    /// tie-break. The renderer calls this once per visible draw.
    func nearestPointLights(to position: SIMD3<Float>, limit: Int) -> [RenderPointLight] {
        guard limit > 0, pointLights.count > limit else { return Array(pointLights.prefix(limit)) }
        return pointLights.enumerated().sorted { lhs, rhs in
            let lhsDistance = simd_length_squared(lhs.element.position - position)
            let rhsDistance = simd_length_squared(rhs.element.position - position)
            return lhsDistance == rhsDistance ? lhs.offset < rhs.offset : lhsDistance < rhsDistance
        }.prefix(limit).map(\.element)
    }

    /// Per-draw uniform ring slots one frame can need: one per group +
    /// terrain item.
    var drawCount: Int {
        opaque.count + alphaTested.count + terrain.count + water.count
    }

    /// Static instances across all groups — sizes the renderer's
    /// per-instance transform ring.
    var instanceCount: Int {
        opaque.reduce(0) { $0 + $1.instances.count }
            + alphaTested.reduce(0) { $0 + $1.instances.count }
    }

    /// Every GPU allocation the scene touches, deduplicated — feeds the
    /// renderer's residency set (todo 2.6 residency rule).
    var residencyAllocations: [MTLAllocation] {
        var seen = Set<ObjectIdentifier>()
        var allocations: [MTLAllocation] = []
        func add(_ resources: [MTLAllocation]) {
            allocations.append(contentsOf: resources.filter {
                seen.insert(ObjectIdentifier($0)).inserted
            })
        }
        for group in opaque + alphaTested {
            var resources: [MTLAllocation] = [
                group.mesh.vertexBuffer, group.mesh.indexBuffer, group.material.diffuse
            ]
            if let skinning = group.mesh.skinningBuffer {
                resources.append(skinning)
            }
            if let matrices = group.mesh.boneMatrixBuffer {
                resources.append(matrices)
            }
            add(resources)
        }
        for item in terrain {
            add([
                item.mesh.vertexBuffer, item.mesh.indexBuffer,
                item.weightsBuffer, item.material.diffuse
            ])
            add(item.layerTextures)
        }
        for item in water {
            add([item.mesh.vertexBuffer, item.mesh.indexBuffer])
        }
        return allocations
    }
}
