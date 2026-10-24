// Distant LOD bridge split from CellSceneBuilder to keep core WRLD walk dense.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyTerrain
import simd

nonisolated extension CellSceneBuilder {
    nonisolated public func buildDistantLOD(
        worldspaceEditorID: String,
        center: CellCoordinate,
        hiddenCells: Set<CellCoordinate>
    ) throws -> DistantLODScene? {
        let lodWorld = lodWorldspace(of: worldspaceEditorID)
        guard let builder = distantLODBuilder else { return nil }
        let lod = try builder.build(worldspace: lodWorld, center: center, hiddenCells: hiddenCells)
            .with(terrainLODBrightness: terrainLODBrightness(lodWorldspace: lodWorld))
        let water = builder.area(worldspace: lodWorld).map {
            distantWater(worldspace: worldspaceEditorID, area: $0, hiddenCells: hiddenCells)
        } ?? []
        return water.isEmpty ? lod : lod.adding(water: water)
    }

    /// A child worldspace with the `PNAM` LOD flag draws its parent's LOD files,
    /// as WhiterunWorld draws Tamriel's.
    nonisolated func lodWorldspace(of editorID: String) -> String {
        let worlds = worldspaceIndexBuildingIfNeeded()
        guard let world = worlds.values.first(where: { $0.editorID == editorID }) else {
            return editorID
        }
        return world.source(of: .useLODData, in: worlds).editorID ?? editorID
    }

    /// Water past the loaded cells, at the `WRLD` LOD water height (`NAM4`), unless
    /// the worldspace sets "no LOD water" (docs/formats/water.md).
    nonisolated func distantWater(
        worldspace editorID: String,
        area: LODWaterLayout.Rectangle,
        hiddenCells: Set<CellCoordinate>
    ) -> [WaterDrawItem] {
        let worlds = worldspaceIndexBuildingIfNeeded()
        guard
            let world = worlds.values.first(where: { $0.editorID == editorID }),
            !world.flags.contains(.noLODWater),
            let mesh = sharedWaterPlane()
        else { return [] }
        let source = world.source(of: .useLODData, in: worlds).details
        let worldWater = resolvedWorldWater(for: world)
        guard let height = source.lodWaterHeight ?? worldWater.height, height.isFinite else {
            return []
        }
        let look = resolvedWaterLook(for: source.lodWater ?? worldWater.type)
        let cell = TerrainMeshBuilder.cellSize
        return LODWaterLayout.rectangles(area: area, hidden: hiddenCells).map { rectangle in
            let origin = SIMD3(
                Float(rectangle.origin.x) * cell, Float(rectangle.origin.y) * cell, height
            )
            let transform = MatrixMath.translation(origin) * float4x4(diagonal: SIMD4(
                Float(rectangle.width), Float(rectangle.height), 1, 1
            ))
            let bounds = ModelBounds(min: .zero, max: SIMD3(cell, cell, 0))
                .transformed(by: transform)
            return WaterDrawItem(mesh: mesh, modelMatrix: transform, look: look, bounds: bounds)
        }
    }
}
