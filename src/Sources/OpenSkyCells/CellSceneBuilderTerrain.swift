// Cell terrain: LAND -> patches -> base and layer textures -> packed weights ->
// splat draw items (docs/rendering/scene-drawing.md). A bad patch or layer is
// counted and skipped.

import Foundation
public import Metal
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
public import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
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
    /// LTEX `INAM`: the ground takes the snow shader.
    var isSnow = false
}

/// One patch's layer textures and aligned opacities, capped at the shader maximum.
nonisolated struct ResolvedTerrainLayers {
    var textures: [any MTLTexture] = []
    var normals: [any MTLTexture] = []
    var resolvedNormals = 0
    var opacities: [[Float]] = []
    var skipped = 0
    /// Bit n: layer n is snow ground.
    var snowLayers: UInt32 = 0
}

nonisolated struct TerrainItemBuild {
    var items: [TerrainDrawItem] = []
    var bounds: ModelBounds?
    var layerCount = 0
    var layerSkipCount = 0
}

nonisolated extension CellSceneBuilder.CellTerrainBuilder {
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
        let built = textures.buildTerrainItems(patches: patches, transform: transform)
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

    /// LAND, else the WRLD DNAM plane (Tamriel -27000), else nothing. The game's
    /// behavior without DNAM is UNCONFIRMED, so no ground is guessed.
    nonisolated private func terrainSource(
        found: FoundCell,
        worldspace: Worldspace?,
        coordinate: CellCoordinate,
        quadFlags: UInt32
    ) -> (patches: [TerrainMeshBuilder.Patch], heightField: TerrainHeightField)? {
        if
            let land = landRecord(in: found, worldspace: worldspace),
            let heights = land.heightField?.heights
        {
            let field = TerrainHeightField(
                coordinate: coordinate,
                heights: heights,
                hiddenQuadrants: quadFlags,
                surfaceMaterials: TerrainSurfaceMaterials.build(
                    land: land,
                    materialTypes: owner.modelIndex.materialTypeIndexBuildingIfNeeded()
                )
            )
            if let field {
                return (
                    TerrainMeshBuilder.patches(land: land, hiddenQuadrants: quadFlags),
                    field
                )
            }
        }
        let worlds = owner.waterBuilder.worldspaceIndexBuildingIfNeeded()
        let landSource = worldspace?.source(of: .useLandData, in: worlds)
        if let height = landSource?.defaultLandHeight {
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

    /// The cell's LAND as the load order has it: the last plugin's decodable
    /// record wins, as for every other cell child.
    nonisolated public func landRecord(in found: FoundCell) -> Land? {
        let later = owner.recordIndex.laterChildren(of: FormID(stored: found.formID), type: "LAND")
        for child in later.reversed() {
            if child.record.record.isDeleted {
                return nil
            }
            if
                let land = owner.records.decodeOrSkip(child.record.record, using: { _ in
                    try child.record.decode(Land.init(record:))
                })
            {
                return land
            }
        }
        return landRecord(in: found.children)
    }

    /// The cell's LAND, else the LAND of the same grid cell in the worldspace it takes its
    /// land from: the city worlds draw Tamriel's ground (docs/formats/world-records.md).
    nonisolated public func landRecord(in found: FoundCell, worldspace: Worldspace?) -> Land? {
        if let land = landRecord(in: found) {
            return land
        }
        guard let worldspace, let grid = found.cell.grid else { return nil }
        let source = worldspace.source(
            of: .useLandData,
            in: owner.waterBuilder.worldspaceIndexBuildingIfNeeded()
        )
        guard source.formID != worldspace.formID else { return nil }
        let parent = FoundWorld(
            children: owner.recordIndex.baseWorldChildren(of: source.formID), worldspace: source,
            formID: source.formID
        )
        return owner.recordIndex.findCell(
            in: parent,
            gridX: grid.x,
            gridY: grid.y,
            localized: owner.pluginLocalized
        )
        .flatMap { landRecord(in: $0) }
    }

    /// The first decodable LAND in the cell's temporary-children group (UESP Groups).
    nonisolated public func landRecord(in cellChildren: ESMGroup?) -> Land? {
        guard
            let cellChildren,
            let children = owner.records.childrenOrSkip(cellChildren) else { return nil }
        for case let .group(group) in children where group.kind == .cellTemporaryChildren {
            guard let records = owner.records.childrenOrSkip(group) else { continue }
            for case let .record(record) in records where record.type == "LAND" {
                guard !record.isDeleted else { continue }
                if let land = owner.records.decodeOrSkip(record, using: Land.init(record:)) {
                    return land
                }
            }
        }
        return nil
    }
}

nonisolated extension CellSceneBuilder {
    public var terrainBuilder: CellSceneBuilder.CellTerrainBuilder {
        CellSceneBuilder.CellTerrainBuilder(owner: self)
    }
}
