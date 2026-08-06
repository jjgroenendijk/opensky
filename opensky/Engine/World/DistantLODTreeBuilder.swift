// Traditional tree LOD build, split from ring selection/terrain placement.

import simd

nonisolated extension DistantLODBuilder {
    struct TreeBuild {
        let placements: [RenderPlacement]
        let blockCount: Int
        let missingBlockCount: Int
    }

    private struct PendingTreePlacement {
        let model: RenderModel
        let transform: float4x4
        let bounds: ModelBounds
    }

    private struct TreePlacementContext {
        let list: TreeLODList
        let atlasPath: String
        let cacheKey: String
        let center: CellCoordinate
        let loadDistance: Float
    }

    func buildTrees(
        worldspace: String,
        settings: LODSettings,
        configuration: TerrainLODConfiguration,
        center: CellCoordinate
    ) throws -> TreeBuild {
        let key = worldspace.lowercased()
        let listPath = "meshes\\terrain\\\(key)\\trees\\\(key).lst"
        guard fileSystem.exists(listPath) else {
            return TreeBuild(placements: [], blockCount: 0, missingBlockCount: 0)
        }
        let list = try treeList(worldspace: key, path: listPath)
        let atlasPath = "textures\\terrain\\\(key)\\trees\\\(key)treelod.dds"
        let radius = max(
            CellGridManager.defaultRadius,
            Int32(ceil(configuration.treeLoadDistance / TerrainMeshBuilder.cellSize))
        )
        let origins = treeBlockOrigins(settings: settings, center: center, radius: radius)
        var placements: [RenderPlacement] = []
        var loadedBlocks = 0
        var missingBlocks = 0
        for origin in origins {
            let path = "meshes\\terrain\\\(key)\\trees\\\(key).4.\(origin.x).\(origin.y).btt"
            guard fileSystem.exists(path) else { continue }
            let block: TreeLODBlock
            do {
                block = try TreeLODBlock(data: fileSystem.contents(forPath: path), list: list)
            } catch {
                missingBlocks += 1
                continue
            }
            loadedBlocks += 1
            let context = TreePlacementContext(
                list: list,
                atlasPath: atlasPath,
                cacheKey: key,
                center: center,
                loadDistance: configuration.treeLoadDistance
            )
            try placements.append(contentsOf: treePlacements(
                block: block,
                context: context
            ))
        }
        return TreeBuild(
            placements: placements,
            blockCount: loadedBlocks,
            missingBlockCount: missingBlocks
        )
    }

    private func treePlacements(
        block: TreeLODBlock,
        context: TreePlacementContext
    ) throws -> [RenderPlacement] {
        var pending: [PendingTreePlacement] = []
        let center = CellGridManager.cellCenter(of: context.center)
        let centerPosition = SIMD2(center.x, center.y)
        for group in block.groups {
            guard let type = context.list.type(index: group.typeIndex) else { continue }
            let sourceModel = TreeLODBillboard.model(type: type, atlasPath: context.atlasPath)
            let model = try meshes.generatedModel(
                key: "tree-lod|\(context.cacheKey)|\(type.index)",
                model: sourceModel
            )
            guard let localBounds = ModelBounds.containing(model: sourceModel) else { continue }
            for reference in group.references {
                let position = SIMD2(reference.position.x, reference.position.y)
                guard simd_distance(position, centerPosition) <= context.loadDistance else {
                    continue
                }
                let transform = MatrixMath.translation(reference.position)
                    * MatrixMath.rotationZ(radians: reference.rotation)
                    * MatrixMath.scale(uniform: reference.scale)
                pending.append(PendingTreePlacement(
                    model: model,
                    transform: transform,
                    bounds: localBounds.transformed(by: transform)
                ))
            }
        }
        return pending.map {
            RenderPlacement(
                model: $0.model,
                transform: $0.transform,
                bounds: $0.bounds,
                castsShadows: false,
                receivesPointLights: false,
                receivesShadows: false
            )
        }
    }

    private func treeList(worldspace: String, path: String) throws -> TreeLODList {
        if let cached = treeListByWorldspace[worldspace] {
            return cached
        }
        let parsed = try TreeLODList(data: fileSystem.contents(forPath: path))
        treeListByWorldspace[worldspace] = parsed
        return parsed
    }

    private func treeBlockOrigins(
        settings: LODSettings,
        center: CellCoordinate,
        radius: Int32
    ) -> [CellCoordinate] {
        let level: Int32 = 4
        let lower = settings.blockOrigin(
            containing: CellCoordinate(x: center.x - radius, y: center.y - radius),
            level: level
        )
        let upper = settings.blockOrigin(
            containing: CellCoordinate(x: center.x + radius, y: center.y + radius),
            level: level
        )
        var origins: [CellCoordinate] = []
        var x = lower.x
        while x <= upper.x {
            var y = lower.y
            while y <= upper.y {
                origins.append(CellCoordinate(x: x, y: y))
                y += level
            }
            x += level
        }
        return origins
    }
}
