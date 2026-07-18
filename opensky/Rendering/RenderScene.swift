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
/// shader consumes. Alpha blending (Material.alphaBlend) is out of 2.6
/// scope and renders opaque for now — noted in docs/rendering/static-mesh.md.
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

/// One draw call: mesh + material + world-space matrices, ready to copy
/// into the per-draw uniform ring.
nonisolated struct DrawItem {
    let mesh: RenderMesh
    let material: RenderMaterial
    let modelMatrix: float4x4
    /// Inverse-transpose of modelMatrix (world-space normals).
    let normalMatrix: float4x4
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
}

/// Flattened draw lists for one frame's scene. Instances are (model,
/// instance transform) pairs; each mesh becomes one DrawItem with
/// modelMatrix = instance * meshLocal. Terrain items carry their own layer
/// textures + weight streams and draw through the terrain splat pipeline.
nonisolated struct RenderScene {
    let opaque: [DrawItem]
    let alphaTested: [DrawItem]
    let terrain: [TerrainDrawItem]

    init(
        instances: [(model: RenderModel, transform: float4x4)],
        terrain: [TerrainDrawItem] = []
    ) {
        var opaque: [DrawItem] = []
        var alphaTested: [DrawItem] = []
        for (model, transform) in instances {
            for mesh in model.meshes {
                // Slot validated against the producing Model by RenderModel
                // construction order; guard anyway — external data upstream.
                guard mesh.materialSlot < model.materials.count else { continue }
                let material = model.materials[mesh.materialSlot]
                let modelMatrix = transform * mesh.localTransform
                let item = DrawItem(
                    mesh: mesh,
                    material: material,
                    modelMatrix: modelMatrix,
                    normalMatrix: MatrixMath.normalMatrix(modelMatrix)
                )
                if material.alphaTestThreshold == nil {
                    opaque.append(item)
                } else {
                    alphaTested.append(item)
                }
            }
        }
        self.opaque = opaque
        self.alphaTested = alphaTested
        self.terrain = terrain
    }

    var drawCount: Int {
        opaque.count + alphaTested.count + terrain.count
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
        for item in opaque + alphaTested {
            add([item.mesh.vertexBuffer, item.mesh.indexBuffer, item.material.diffuse])
        }
        for item in terrain {
            add([
                item.mesh.vertexBuffer, item.mesh.indexBuffer,
                item.weightsBuffer, item.material.diffuse
            ])
            add(item.layerTextures)
        }
        return allocations
    }
}
