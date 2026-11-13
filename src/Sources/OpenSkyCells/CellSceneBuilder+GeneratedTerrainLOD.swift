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

nonisolated extension CellSceneBuilder.CellTerrainLODBuilder {
    /// One worldspace's generated terrain, built on the cell build queue.
    final class LoadOrderTerrainLOD: TerrainLODGenerating {
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
                self.builder.terrainBuilder.terrainLOD.terrainLODTexture($0, edge: edge)
            }
            let normal = TerrainLODGenerator.normalMap(source)
            let side = TerrainLODGenerator.textureSize
            return GeneratedTerrainBlock(
                model: TerrainLODGenerator.model(
                    source, diffuseKey: block.generatedDiffuseKey,
                    normalKey: block.generatedNormalKey
                ),
                diffuse: DDSEncoder.rgba8888(DecodedImage(
                    width: side,
                    height: side,
                    rgba: diffuse
                )),
                normal: DDSEncoder.rgba8888(DecodedImage(width: side, height: side, rgba: normal))
            )
        }

        /// Nil when no cell of the block has land.
        func source(for block: DistantLODBlock) -> TerrainLODGenerator.Source? {
            var cells: [TerrainLODLand?] = []
            cells.reserveCapacity(Int(block.level * block.level))
            for row in 0 ..< block.level {
                for column in 0 ..< block.level {
                    let found = builder.recordIndex.findCell(
                        in: world, gridX: block.origin.x + column, gridY: block.origin.y + row,
                        localized: builder.pluginLocalized
                    )
                    cells.append(found.flatMap { builder.terrainBuilder.landRecord(in: $0) }
                        .flatMap(TerrainLODLand.init(land:)))
                }
            }
            guard cells.contains(where: { $0 != nil }) else { return nil }
            return TerrainLODGenerator.Source(
                level: block.level, cells: cells, defaultHeight: defaultHeight
            )
        }
    }
}

nonisolated extension CellSceneBuilder.CellTerrainLODBuilder {
    /// The generator for the LOD worldspace, or nil when generated terrain is off or the
    /// worldspace is not in the load order.
    nonisolated func loadOrderTerrainLOD(lodWorldspace: String) -> LoadOrderTerrainLOD? {
        guard
            let store = owner.distantLODBuilder?.configurationStore,
            store.snapshot().configuration.generatedTerrain,
            let world = attempt({
                try owner.records.worldChildrenGroup(
                    editorID: lodWorldspace,
                    localized: owner.pluginLocalized
                )
            })
        else { return nil }
        let worlds = owner.waterBuilder.worldspaceIndexBuildingIfNeeded()
        let height = world.worldspace?.source(of: .useLandData, in: worlds).defaultLandHeight
        return LoadOrderTerrainLOD(builder: owner, world: world, defaultHeight: height ?? -2048)
    }

    /// A land texture at the mip whose edge is closest above `edge`; nil when its chain
    /// is broken or the CPU cannot decode it.
    nonisolated func terrainLODTexture(_ ltexID: FormID, edge: Int) -> TerrainLODTexture? {
        guard let path = owner.terrainBuilder.textures.terrainTextureKeys(for: ltexID)?.diffuse
        else { return nil }
        let key = "\(path)|\(edge)"
        if let cached = owner.caches.terrainLODTextures[key] {
            return cached
        }
        let image = attempt { try owner.fileSystem?.contents(forPath: path) }
            .flatMap { element in attempt { try DDSDecoder.smallLevel(element, edge: edge) } }
        let texture = image.flatMap {
            TerrainLODTexture(width: $0.width, height: $0.height, rgba: $0.rgba)
        }
        owner.caches.terrainLODTextures[key] = .some(texture)
        return texture
    }
}
