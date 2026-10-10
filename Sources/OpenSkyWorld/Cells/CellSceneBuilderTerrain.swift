// Cell terrain: LAND -> patches -> base and layer textures -> packed weights ->
// splat draw items (docs/rendering/scene-drawing.md). A bad patch or layer is
// counted and skipped.

import Foundation
import Metal
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyRendering
import OpenSkyShaderTypes
import simd

/// Splat draw items, world bounds, and the layer counts for the summary.
nonisolated public struct TerrainBuild {
    public let items: [TerrainDrawItem]
    public let bounds: ModelBounds?
    public let heightField: TerrainHeightField
    public let quadrantCount: Int
    /// ATXT layers drawn across all quadrants.
    public let layerCount: Int
    /// Layers dropped: unresolvable LTEX/TXST chain or over the format cap.
    public let layerSkipCount: Int
}

/// The TXST paths of one land texture: TX00 diffuse, and TX01 normal when set.
nonisolated struct TerrainTextureKeys: Equatable {
    let diffuse: String
    let normal: String?
}

/// One patch's layer textures and aligned opacities, capped at the shader maximum.
nonisolated private struct ResolvedTerrainLayers {
    var textures: [MTLTexture] = []
    var normals: [MTLTexture] = []
    var resolvedNormals = 0
    var opacities: [[Float]] = []
    var skipped = 0
}

nonisolated private struct TerrainItemBuild {
    var items: [TerrainDrawItem] = []
    var bounds: ModelBounds?
    var layerCount = 0
    var layerSkipCount = 0
}

nonisolated extension CellSceneBuilder {
    /// From LAND, else a flat plane at the WRLD DNAM height; nil if neither
    /// uploads. The south-west corner sits at (gridX*4096, gridY*4096)
    /// (docs/decisions/coordinates.md).
    nonisolated public func buildTerrain(
        found: FoundCell,
        worldspace: Worldspace?
    ) -> TerrainBuild? {
        guard let grid = found.cell.grid else { return nil }
        let coordinate = CellCoordinate(x: grid.x, y: grid.y)
        let source = terrainSource(
            found: found,
            worldspace: worldspace,
            coordinate: coordinate,
            quadFlags: grid.quadFlags
        )
        guard let source else { return nil }
        let patches = source.patches
        guard !patches.isEmpty else { return nil }

        let origin = SIMD3<Float>(Float(grid.x) * 4096, Float(grid.y) * 4096, 0)
        let transform = MatrixMath.translation(origin)
        let built = buildTerrainItems(patches: patches, transform: transform)
        guard !built.items.isEmpty else { return nil }
        return TerrainBuild(
            items: built.items,
            bounds: built.bounds,
            heightField: source.heightField,
            quadrantCount: built.items.count,
            layerCount: built.layerCount,
            layerSkipCount: built.layerSkipCount
        )
    }

    nonisolated private func buildTerrainItems(
        patches: [TerrainMeshBuilder.Patch],
        transform: float4x4
    ) -> TerrainItemBuild {
        let normalMatrix = MatrixMath.normalMatrix(transform)
        var built = TerrainItemBuild()
        for patch in patches {
            let resolved = resolveTerrainLayers(patch.layers)
            built.layerSkipCount += resolved.skipped
            do {
                let upload = try meshes.terrainMesh(
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
                    base: textures.texture(key: baseNormalKey, usage: .data),
                    layers: resolved.normals,
                    resolvedCount: resolved.resolvedNormals + (baseNormalKey == nil ? 0 : 1)
                )
                built.items.append(TerrainDrawItem(
                    mesh: upload.mesh,
                    weightsBuffer: upload.weightsBuffer,
                    material: RenderMaterial(
                        material: terrainBaseMaterial(for: patch.baseTexture),
                        textureProvider: textures.provider
                    ),
                    layerTextures: resolved.textures,
                    normals: normals,
                    modelMatrix: transform,
                    normalMatrix: normalMatrix,
                    bounds: world
                ))
                built.layerCount += resolved.textures.count
                if let world {
                    built.bounds = built.bounds.map { $0.union(world) } ?? world
                }
            } catch {
                let reason = String(describing: error)
                Self.logger.warning(
                    "terrain patch upload failed (\(reason, privacy: .public)), skipped"
                )
            }
        }
        return built
    }

    /// LAND, else the WRLD DNAM plane (Tamriel -27000), else nothing. The game's
    /// behavior without DNAM is UNCONFIRMED, so no ground is guessed.
    nonisolated private func terrainSource(
        found: FoundCell,
        worldspace: Worldspace?,
        coordinate: CellCoordinate,
        quadFlags: UInt32
    ) -> (patches: [TerrainMeshBuilder.Patch], heightField: TerrainHeightField)? {
        if let land = landRecord(in: found) {
            if let heights = land.heightField?.heights {
                let field = TerrainHeightField(
                    coordinate: coordinate,
                    heights: heights,
                    hiddenQuadrants: quadFlags,
                    surfaceMaterials: TerrainSurfaceMaterials.build(
                        land: land,
                        materialTypes: materialTypeIndexBuildingIfNeeded()
                    )
                )
                if let field {
                    return (
                        TerrainMeshBuilder.patches(land: land, hiddenQuadrants: quadFlags),
                        field
                    )
                }
            }
        }
        if let height = worldspace?.defaultLandHeight {
            let field = TerrainHeightField(
                coordinate: coordinate,
                heights: [Float](repeating: height, count: Land.vertexCount)
            )
            if let field {
                return ([TerrainMeshBuilder.fallbackPatch(defaultLandHeight: height)], field)
            }
        }
        return nil
    }

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
                Self.logger.warning(
                    "terrain layer LTEX \(id, privacy: .public) unresolvable, dropped"
                )
                continue
            }
            guard resolved.textures.count < TerrainConstant.maxLayers.rawValue else {
                resolved.skipped += 1
                Self.logger.warning("terrain quadrant over the layer cap, extra dropped")
                continue
            }
            resolved.textures.append(textures.texture(key: keys.diffuse, usage: .color))
            resolved.normals.append(textures.texture(key: keys.normal, usage: .data))
            resolved.resolvedNormals += keys.normal == nil ? 0 : 1
            resolved.opacities.append(layer.opacities)
        }
        return resolved
    }

    /// The cell's LAND as the load order has it: the last plugin's decodable
    /// record wins, as for every other cell child.
    nonisolated public func landRecord(in found: FoundCell) -> Land? {
        let later = laterChildren(of: FormID(stored: found.formID), type: "LAND")
        for child in later.reversed() {
            if child.record.record.isDeleted {
                return nil
            }
            if
                let land = decodeOrSkip(child.record.record, using: { _ in
                    try child.record.decode(Land.init(record:))
                })
            {
                return land
            }
        }
        return landRecord(in: found.children)
    }

    /// The first decodable LAND in the cell's temporary-children group (UESP Groups).
    nonisolated public func landRecord(in cellChildren: ESMGroup?) -> Land? {
        guard let cellChildren, let children = childrenOrSkip(cellChildren) else { return nil }
        for case let .group(group) in children where group.kind == .cellTemporaryChildren {
            guard let records = childrenOrSkip(group) else { continue }
            for case let .record(record) in records where record.type == "LAND" {
                guard !record.isDeleted else { continue }
                if let land = decodeOrSkip(record, using: Land.init(record:)) {
                    return land
                }
            }
        }
        return nil
    }

    /// LTEX TNAM -> TXST TX00 and TX01, normalized like NIF materials. Nil on any
    /// broken link or a missing diffuse (docs/engine/terrain.md).
    nonisolated private func terrainTextureKeys(for ltexID: FormID) -> TerrainTextureKeys? {
        if let cached = terrainTextureKeyCache[ltexID.rawValue] {
            return cached
        }
        let keys = uncachedTerrainTextureKeys(for: ltexID)
        terrainTextureKeyCache[ltexID.rawValue] = .some(keys)
        return keys
    }

    /// A null LTEX resolves to the default ground texture (docs/formats/land.md).
    nonisolated private func uncachedTerrainTextureKeys(for ltexID: FormID) -> TerrainTextureKeys? {
        guard
            let ltex = landTextureIndexBuildingIfNeeded()[ltexID.rawValue],
            let textureSet = ltex.textureSet,
            let txst = textureSetIndexBuildingIfNeeded()[textureSet.rawValue],
            let diffuse = txst.diffusePath.flatMap({ NIFShaderTextureSet.vfsKey(for: $0) })
        else { return nil }
        return TerrainTextureKeys(
            diffuse: diffuse,
            normal: txst.normalPath.flatMap { NIFShaderTextureSet.vfsKey(for: $0) }
        )
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
}
