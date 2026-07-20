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
    let staticCollision: StaticCollisionSet
    /// Assembled actor placements + exact accounting (5.5 actor streaming).
    let actors: CellActorBuild
}

/// Exterior environment trio built beside the placed models.
nonisolated struct EnvironmentBuild {
    let terrain: TerrainBuild?
    let water: WaterBuild?
    let sky: SkyParameters?
}

extension CellSceneBuilder {
    /// Terrain + water + procedural sky (suppressed for noSky worldspaces).
    nonisolated func buildEnvironment(
        found: FoundCell,
        worldspace: Worldspace?
    ) -> EnvironmentBuild {
        EnvironmentBuild(
            terrain: buildTerrain(found: found, worldspace: worldspace),
            water: buildWater(found: found, worldspace: worldspace),
            sky: worldspace?.flags.contains(.noSky) == false ? SkyParameters() : nil
        )
    }

    /// Keeps only REFRs whose base resolves to DOOR and whose XTEL decoded.
    /// A non-teleport door still renders but has no activation target.
    nonisolated func resolveDoors(refs: [PlacedReference]) -> [PlacedDoor] {
        let modelBaseIndex = modelBaseIndexBuildingIfNeeded()
        return refs.compactMap { ref in
            guard
                modelBaseIndex[ref.base.rawValue]?.recordType == "DOOR",
                let destination = ref.teleportDestination
            else { return nil }
            return PlacedDoor(
                reference: ref.formID,
                position: ref.placement.position,
                destination: destination
            )
        }
    }

    /// RenderScene handles opaque/alpha-test order; environment adds terrain,
    /// water, sky. Model + geometry AABBs feed framing and frustum culling.
    nonisolated func makeScene(
        found: FoundCell,
        grid: (x: Int32, y: Int32),
        instances: [ResolvedInstance],
        geometry: CellGeometryBuild,
        counts: BuildCounts
    ) -> CellScene {
        let actors = geometry.actors
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
        for placement in actors.placements {
            guard let world = placement.bounds else { continue }
            bounds = bounds.map { $0.union(world) } ?? world
        }
        let renderScene = RenderScene(
            instances: placed + actors.placements,
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
            terrainHeightField: geometry.terrain?.heightField,
            staticCollision: geometry.staticCollision
        )
    }

    nonisolated private func makeSummary(
        found: FoundCell,
        grid: (x: Int32, y: Int32),
        instanceCount: Int,
        geometry: CellGeometryBuild,
        counts: BuildCounts
    ) -> CellLoadSummary {
        let actors = geometry.actors
        var summary = CellLoadSummary(
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
        summary.actorCount = actors.counts.discovered
        summary.actorDrawnCount = actors.counts.rendered
        summary.actorDisabledSkipCount = actors.counts.disabledSkips
        summary.actorFailureCount = actors.counts.failures
        summary.actorFailureReasons = actors.counts.failureReasons
        summary.actorBuildDurationMS = actors.durationMS
        return summary
    }
}
