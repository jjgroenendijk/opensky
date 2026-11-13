// The texture layers and render items of a terrain cell.

import Foundation
import Metal
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyShaderTypes
import simd

nonisolated extension CellSceneBuilder.CellTerrainTextures {
    /// A broken LTEX -> TXST chain drops the layer and its weight lane, so the
    /// rest stay aligned. Layers past `TerrainConstant.maxLayers` also drop
    /// (docs/formats/land.md).
    nonisolated private func resolveTerrainLayers(
        _ layers: [TerrainMeshBuilder.Layer]
    ) -> ResolvedTerrainLayers {
        var resolved = ResolvedTerrainLayers()
        for layer in layers {
            guard let keys = terrainTextureKeys(for: layer.texture) else {
                resolved.skipped += 1
                let id = layer.texture.description
                CellSceneBuilder.logger.warning(
                    "terrain layer LTEX \(id, privacy: .public) unresolvable, dropped"
                )
                continue
            }
            guard resolved.textures.count < TerrainConstant.maxLayers.rawValue else {
                resolved.skipped += 1
                CellSceneBuilder.logger
                    .warning("terrain quadrant over the layer cap, extra dropped")
                continue
            }
            if keys.isSnow {
                resolved.snowLayers |= 1 << UInt32(resolved.textures.count)
            }
            resolved.textures.append(owner.textures.texture(key: keys.diffuse, usage: .color))
            resolved.normals.append(owner.textures.texture(key: keys.normal, usage: .data))
            resolved.resolvedNormals += keys.normal == nil ? 0 : 1
            resolved.opacities.append(layer.opacities)
        }
        return resolved
    }

    /// The BTXT base material, or `Material.fallback` when unpainted or broken.
    nonisolated private func terrainBaseMaterial(for baseTexture: FormID?) -> Material {
        guard let baseTexture, let diffuse = terrainTextureKeys(for: baseTexture)?.diffuse else {
            return .fallback
        }
        let fallback = Material.fallback
        return Material(
            diffuseTexture: diffuse,
            normalTexture: nil,
            uvOffset: fallback.uvOffset,
            uvScale: fallback.uvScale,
            alpha: fallback.alpha,
            glossiness: fallback.glossiness,
            specularColor: fallback.specularColor,
            specularStrength: fallback.specularStrength,
            doubleSided: false,
            alphaBlend: false,
            alphaTestThreshold: nil
        )
    }

    /// LTEX TNAM -> TXST TX00 and TX01, normalized like NIF materials. Nil on any
    /// broken link or a missing diffuse (docs/engine/terrain.md).
    nonisolated func terrainTextureKeys(for ltexID: FormID) -> TerrainTextureKeys? {
        if let cached = owner.caches.terrainTextureKeyCache[ltexID.rawValue] {
            return cached
        }
        let keys = uncachedTerrainTextureKeys(for: ltexID)
        owner.caches.terrainTextureKeyCache[ltexID.rawValue] = .some(keys)
        return keys
    }

    /// A null LTEX resolves to the default ground texture (docs/formats/land.md).
    nonisolated private func uncachedTerrainTextureKeys(for ltexID: FormID) -> TerrainTextureKeys? {
        guard
            let ltex = owner.terrainBuilder.grass
                .landTextureIndexBuildingIfNeeded()[ltexID.rawValue],
            let textureSet = ltex.textureSet,
            let txst = owner.modelIndex.textureSetIndexBuildingIfNeeded()[textureSet.rawValue],
            let diffuse = txst.diffusePath.flatMap({ NIFShaderTextureSet.vfsKey(for: $0) })
        else { return nil }
        return TerrainTextureKeys(
            diffuse: diffuse,
            normal: txst.normalPath.flatMap { NIFShaderTextureSet.vfsKey(for: $0) },
            isSnow: ltex.isSnow
        )
    }

    nonisolated func buildTerrainItems(
        patches: [TerrainMeshBuilder.Patch],
        transform: float4x4
    ) -> TerrainItemBuild {
        let normalMatrix = MatrixMath.normalMatrix(transform)
        var built = TerrainItemBuild()
        for patch in patches {
            let resolved = resolveTerrainLayers(patch.layers)
            built.layerSkipCount += resolved.skipped
            do {
                let upload = try owner.meshes.terrainMesh(
                    patch.mesh,
                    weights:
                    TerrainMeshBuilder.packWeights(
                        layers: resolved.opacities,
                        vertexCount: patch.mesh.positions.count
                    )
                )
                let world = ModelBounds.containing(patch.mesh.positions)?
                    .transformed(by: transform)
                let baseNormalKey = patch.baseTexture.flatMap { terrainTextureKeys(for: $0) }?
                    .normal
                let normals = TerrainNormalMaps(
                    base: owner.textures.texture(key: baseNormalKey, usage: .data),
                    layers: resolved.normals
                )
                let baseSnow = patch.baseTexture.flatMap { terrainTextureKeys(for: $0) }?
                    .isSnow == true
                built.items.append(TerrainDrawItem(
                    mesh: upload.mesh,
                    weightsBuffer: upload.weightsBuffer,
                    material: RenderMaterial(
                        material: terrainBaseMaterial(for: patch.baseTexture),
                        textureProvider: owner.textures.provider
                    ),
                    layerTextures: resolved.textures,
                    normals: normals,
                    modelMatrix: transform,
                    normalMatrix: normalMatrix,
                    bounds: world,
                    snowLayers: resolved.snowLayers
                        | (baseSnow ? TerrainDrawItem.snowBaseBit : 0)
                ))
                built.layerCount += resolved.textures.count
                if let world {
                    built.bounds = built.bounds.map { $0.union(world) } ?? world
                }
            } catch {
                let reason = String(describing: error)
                CellSceneBuilder.logger.warning(
                    "terrain patch upload failed (\(reason, privacy: .public)), skipped"
                )
            }
        }
        return built
    }
}
