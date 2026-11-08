// Feeds the terrain LOD generator from the load order: each block reads the winning
// LAND of its cells and samples the land textures at a small mip
// (docs/engine/distant-lod.md#generated-terrain).

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyImageKernels
import OpenSkyRenderCore
import OpenSkyTerrain

/// One worldspace's generated terrain, built on the cell build queue.
nonisolated final class LoadOrderTerrainLOD: TerrainLODGenerating {
    private unowned let builder: CellSceneBuilder
    private let world: FoundWorld
    private let defaultHeight: Float

    init(builder: CellSceneBuilder, world: FoundWorld, defaultHeight: Float) {
        self.builder = builder
        self.world = world
        self.defaultHeight = defaultHeight
    }

    func terrainBlock(_ block: DistantLODBlock) -> GeneratedTerrainBlock? {
        guard let source = source(for: block) else { return nil }
        let edge = TerrainLODGenerator.textureEdge(level: block.level)
        let diffuse = TerrainLODGenerator.diffuse(source) {
            self.builder.terrainLODTexture($0, edge: edge)
        }
        let normal = TerrainLODGenerator.normalMap(source)
        let side = TerrainLODGenerator.textureSize
        return GeneratedTerrainBlock(
            model: TerrainLODGenerator.model(
                source, diffuseKey: block.generatedDiffuseKey, normalKey: block.generatedNormalKey
            ),
            diffuse: DDSEncoder.rgba8888(DecodedImage(width: side, height: side, rgba: diffuse)),
            normal: DDSEncoder.rgba8888(DecodedImage(width: side, height: side, rgba: normal))
        )
    }

    /// Nil when no cell of the block has land.
    func source(for block: DistantLODBlock) -> TerrainLODGenerator.Source? {
        var cells: [TerrainLODLand?] = []
        cells.reserveCapacity(Int(block.level * block.level))
        for row in 0 ..< block.level {
            for column in 0 ..< block.level {
                let found = builder.findCell(
                    in: world, gridX: block.origin.x + column, gridY: block.origin.y + row,
                    localized: builder.pluginLocalized
                )
                cells.append(found.flatMap { builder.landRecord(in: $0) }
                    .flatMap(TerrainLODLand.init(land:)))
            }
        }
        guard cells.contains(where: { $0 != nil }) else { return nil }
        return TerrainLODGenerator.Source(
            level: block.level, cells: cells, defaultHeight: defaultHeight
        )
    }
}

nonisolated extension CellSceneBuilder {
    /// The generator for the LOD worldspace, or nil when generated terrain is off or the
    /// worldspace is not in the load order.
    nonisolated func loadOrderTerrainLOD(lodWorldspace: String) -> LoadOrderTerrainLOD? {
        guard
            let store = distantLODBuilder?.configurationStore,
            store.snapshot().configuration.generatedTerrain,
            let world = attempt({
                try worldChildrenGroup(
                    editorID: lodWorldspace,
                    localized: pluginLocalized
                )
            })
        else { return nil }
        let worlds = worldspaceIndexBuildingIfNeeded()
        let height = world.worldspace?.source(of: .useLandData, in: worlds).defaultLandHeight
        return LoadOrderTerrainLOD(builder: self, world: world, defaultHeight: height ?? -2048)
    }

    /// A land texture at the mip whose edge is closest above `edge`; nil when its chain
    /// is broken or the CPU cannot decode it.
    nonisolated func terrainLODTexture(_ ltexID: FormID, edge: Int) -> TerrainLODTexture? {
        guard let path = terrainTextureKeys(for: ltexID)?.diffuse else { return nil }
        let key = "\(path)|\(edge)"
        if let cached = terrainLODTextures[key] {
            return cached
        }
        let image = attempt { try fileSystem?.contents(forPath: path) }
            .flatMap { element in attempt { try DDSDecoder.smallLevel(element, edge: edge) } }
        let texture = image.flatMap {
            TerrainLODTexture(width: $0.width, height: $0.height, rgba: $0.rgba)
        }
        terrainLODTextures[key] = .some(texture)
        return texture
    }
}
