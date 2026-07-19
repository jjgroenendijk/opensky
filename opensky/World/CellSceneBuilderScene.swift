// Final CellScene assembly split from CellSceneBuilder.swift for file-length
// limits: flatten placed models, attach terrain/environment draws, union
// bounds, emit one load summary.

import OSLog

nonisolated struct CellGeometryBuild {
    let location: CellSceneLocation
    let doors: [PlacedDoor]
    let terrain: TerrainBuild?
    let water: WaterBuild?
    let sky: SkyParameters?
    let lighting: RenderLighting?
    let pointLights: [RenderPointLight]
}

extension CellSceneBuilder {
    /// RenderScene handles opaque/alpha-test order; environment adds terrain,
    /// water, sky. Model + geometry AABBs feed framing and frustum culling.
    nonisolated func makeScene(
        found: FoundCell,
        grid: (x: Int32, y: Int32),
        instances: [ResolvedInstance],
        geometry: CellGeometryBuild,
        counts: BuildCounts
    ) -> CellScene {
        var bounds: ModelBounds?
        let placed = instances.map { instance -> RenderPlacement in
            let world = meshes.bounds(forPath: instance.modelPath)?
                .transformed(by: instance.transform)
            if let world {
                bounds = bounds.map { $0.union(world) } ?? world
            }
            return RenderPlacement(
                model: instance.model,
                transform: instance.transform,
                bounds: world
            )
        }
        let renderScene = RenderScene(
            instances: placed,
            terrain: geometry.terrain?.items ?? [],
            water: geometry.water.map { [$0.item] } ?? [],
            sky: found.cell.isInterior ? nil : geometry.sky,
            lighting: geometry.lighting,
            pointLights: geometry.pointLights
        )
        if let world = geometry.terrain?.bounds {
            bounds = bounds.map { $0.union(world) } ?? world
        }
        if let world = geometry.water?.item.bounds {
            bounds = bounds.map { $0.union(world) } ?? world
        }
        let summary = makeSummary(
            found: found,
            grid: grid,
            instanceCount: instances.count,
            geometry: geometry,
            counts: counts
        )
        Self.logger.info("\(summary.summaryLine, privacy: .public)")
        return CellScene(
            renderScene: renderScene,
            summary: summary,
            bounds: bounds.map { (min: $0.min, max: $0.max) },
            location: geometry.location,
            doors: geometry.doors,
            terrainHeightField: geometry.terrain?.heightField
        )
    }

    nonisolated private func makeSummary(
        found: FoundCell,
        grid: (x: Int32, y: Int32),
        instanceCount: Int,
        geometry: CellGeometryBuild,
        counts: BuildCounts
    ) -> CellLoadSummary {
        CellLoadSummary(
            cellName: found.cell.editorID ?? "cell \(FormID(found.formID).description)",
            gridX: grid.x,
            gridY: grid.y,
            totalRefCount: counts.totalRefs,
            drawnRefCount: instanceCount,
            unsupportedBaseSkipCount: counts.unsupportedBases,
            markerSkipCount: counts.markers,
            modelFailureSkipCount: counts.modelFailures,
            malformedRefSkipCount: counts.malformedRefs,
            modelCount: meshes.loadedCount,
            textureCount: textures.loadedCount,
            missingTextureCount: textures.missingCount,
            terrainQuadrantCount: geometry.terrain?.quadrantCount ?? 0,
            terrainLayerCount: geometry.terrain?.layerCount ?? 0,
            terrainLayerSkipCount: geometry.terrain?.layerSkipCount ?? 0,
            waterPlaneCount: geometry.water == nil ? 0 : 1,
            pointLightCount: geometry.pointLights.count
        )
    }
}
