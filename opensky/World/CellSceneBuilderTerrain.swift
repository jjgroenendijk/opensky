// Terrain half of the cell scene build (todo 3.1), split from
// CellSceneBuilder.swift for file-length limits (RendererSetup.swift
// precedent): LAND -> TerrainMeshBuilder patches -> resolved base + layer
// textures -> packed weights -> TerrainDrawItems for the splat pipeline
// (docs/rendering/metal4-renderer.md, terrain splat section). Per-patch and
// per-layer failures log + skip + count, never abort the build (AGENTS.md
// mod-quirk rule).

import Foundation
import Metal
import OSLog
import simd

/// Built terrain ready to fold into the scene: splat draw items for the
/// terrain pipeline, world-space bounds, and the layer accounting the
/// summary reports.
nonisolated struct TerrainBuild {
    let items: [TerrainDrawItem]
    let bounds: ModelBounds?
    let heightField: TerrainHeightField
    let quadrantCount: Int
    /// ATXT layers drawn across all quadrants.
    let layerCount: Int
    /// Layers dropped: unresolvable LTEX/TXST chain or over the format cap.
    let layerSkipCount: Int
}

/// Post-resolution splat layers for one patch: textures + aligned opacity
/// arrays capped at the shader's layer maximum, plus the drop count.
nonisolated private struct ResolvedTerrainLayers {
    var textures: [MTLTexture] = []
    var opacities: [[Float]] = []
    var skipped = 0
}

nonisolated private struct TerrainItemBuild {
    var items: [TerrainDrawItem] = []
    var bounds: ModelBounds?
    var layerCount = 0
    var layerSkipCount = 0
}

extension CellSceneBuilder {
    /// Builds terrain for the cell: from its LAND record when present, else a
    /// flat fallback plane at the worldspace DNAM default land height. Returns
    /// nil (no terrain drawn) when neither is available or every upload fails —
    /// terrain never aborts the cell build (mod-quirk rule). Placement puts the
    /// cell's south-west corner at (gridX*4096, gridY*4096), matching REFR world
    /// coordinates (docs/decisions/coordinates.md) so vertex local (col*128,
    /// row*128, height) lands at absolute world position.
    nonisolated func buildTerrain(found: FoundCell, worldspace: Worldspace?) -> TerrainBuild? {
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
                // World AABB per patch: feeds the draw item (frustum culling)
                // and the terrain-wide bounds (camera framing).
                let world = ModelBounds.containing(patch.mesh.positions)?
                    .transformed(by: transform)
                built.items.append(TerrainDrawItem(
                    mesh: upload.mesh,
                    weightsBuffer: upload.weightsBuffer,
                    material: RenderMaterial(
                        material: terrainBaseMaterial(for: patch.baseTexture),
                        textureProvider: textures.provider
                    ),
                    layerTextures: resolved.textures,
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

    /// Patch source: LAND when present, else the WRLD DNAM fallback plane,
    /// else nothing. LAND-less exterior cell -> flat plane at the default
    /// land height (Tamriel -27000). When DNAM is absent the correct engine
    /// behavior is UNCONFIRMED (todo: probe); OpenSky draws no ground rather
    /// than guess a floor height that could sit wrong.
    nonisolated private func terrainSource(
        found: FoundCell,
        worldspace: Worldspace?,
        coordinate: CellCoordinate,
        quadFlags: UInt32
    ) -> (patches: [TerrainMeshBuilder.Patch], heightField: TerrainHeightField)? {
        if let land = landRecord(in: found.children) {
            if let heights = land.heightField?.heights {
                let field = TerrainHeightField(
                    coordinate: coordinate,
                    heights: heights,
                    hiddenQuadrants: quadFlags
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

    /// Resolves each ATXT layer's LTEX -> TXST diffuse. A broken chain drops
    /// the layer (and its weight lane) so surviving layers stay aligned with
    /// the packed weight stream; drops are counted, never fatal. Layers past
    /// the shader's TerrainConstant.maxLayers bind slots (format max 8, never
    /// seen in vanilla — docs/formats/land.md) drop defensively.
    nonisolated private func resolveTerrainLayers(
        _ layers: [TerrainMeshBuilder.Layer]
    ) -> ResolvedTerrainLayers {
        var resolved = ResolvedTerrainLayers()
        for layer in layers {
            guard let key = terrainDiffuseKey(for: layer.texture) else {
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
            resolved.textures.append(textures.texture(key: key, usage: .color))
            resolved.opacities.append(layer.opacities)
        }
        return resolved
    }

    /// First LAND record in the cell's temporary-children group (type 9), where
    /// landscape lives (UESP Groups). Malformed decode -> nil (log + skip).
    nonisolated func landRecord(in cellChildren: ESMGroup?) -> Land? {
        guard let cellChildren, let children = try? cellChildren.children() else { return nil }
        for case let .group(group) in children where group.kind == .cellTemporaryChildren {
            guard let records = try? group.children() else { continue }
            for case let .record(record) in records where record.type == "LAND" {
                guard !record.isDeleted else { continue }
                if let land = try? Land(record: record) {
                    return land
                }
                let id = FormID(record.formID).description
                Self.logger.warning("malformed LAND \(id, privacy: .public) skipped")
            }
        }
        return nil
    }

    /// Resolves an LTEX FormID to its TXST TX00 diffuse VFS key: LTEX (TNAM)
    /// -> TXST -> TX00, canonicalized through NIFShaderTextureSet.vfsKey (the
    /// same normalization the NIF material path uses). Any broken link ->
    /// nil. Raw FormIDs suffice while scene build reads one plugin (same rule
    /// as STAT lookup). Normal maps (TX01) stay unused — the splat path is
    /// diffuse-only like the M2 static pipeline (docs/engine/terrain.md).
    nonisolated private func terrainDiffuseKey(for ltexID: FormID) -> String? {
        guard
            let ltexRecord = ESMWalk.record(withFormID: ltexID.rawValue, in: file),
            let ltex = try? LandTexture(record: ltexRecord),
            let textureSet = ltex.textureSet,
            let txstRecord = ESMWalk.record(withFormID: textureSet.rawValue, in: file),
            let txst = try? TextureSet(record: txstRecord)
        else { return nil }
        return txst.diffusePath.flatMap { NIFShaderTextureSet.vfsKey(for: $0) }
    }

    /// Material for a quadrant's BTXT base. Unpainted quadrant or broken
    /// LTEX/TXST chain -> Material.fallback (TextureLibrary placeholders the
    /// unresolved diffuse path).
    nonisolated private func terrainBaseMaterial(for baseTexture: FormID?) -> Material {
        guard let baseTexture, let diffuse = terrainDiffuseKey(for: baseTexture) else {
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
