// Final CellScene assembly split from CellSceneBuilder.swift for file-length
// limits: flatten placed models, attach terrain/environment draws, union
// bounds, emit one load summary.

import OSLog

nonisolated struct CellGeometryBuild {
    let location: CellSceneLocation
    let doors: [PlacedDoor]
    let interactions: [FormID: PlacedInteraction]
    let terrain: TerrainBuild?
    let grass: GrassBuild?
    let water: WaterBuild?
    let sky: SkyParameters?
    let lighting: RenderLighting?
    let pointLights: [RenderPointLight]
    let staticCollision: StaticCollisionSet
    /// Authored trigger volumes (issue #173). `var` with a default so a build
    /// that predates trigger collection still constructs.
    var triggerVolumes: TriggerVolumeSet = .empty
    /// Assembled actor placements + exact accounting (5.5 actor streaming).
    let actors: CellActorBuild
    /// WRLD.ZNAM of the owning worldspace (M9.2.3 music selection). `var` with
    /// a default so the interior path, which has no worldspace, omits it.
    var worldspaceMusicType: FormID?
    /// Runtime index entries for this cell's REFRs (issue #158). Actor entries
    /// travel inside `actors` and are merged in by makeScene.
    var referenceEntries: [RuntimeReferenceEntry] = []
    /// Journal sequence of the world-state snapshot this build applied
    /// (issue #160); 0 for a build with no runtime state behind it.
    var stateSequence: UInt64 = 0

    /// Statics and actors share one per-cell index; both are placements the
    /// runtime addresses by `ReferenceKey`.
    var referenceIndex: RuntimeReferenceIndex {
        RuntimeReferenceIndex(entries: referenceEntries + actors.entries)
    }
}

/// Exterior environment trio built beside the placed models.
nonisolated struct EnvironmentBuild {
    let terrain: TerrainBuild?
    let grass: GrassBuild?
    let water: WaterBuild?
    let sky: SkyParameters?
}

nonisolated extension CellSceneBuilder {
    /// Terrain + water + procedural sky (suppressed for noSky worldspaces).
    nonisolated func buildEnvironment(
        found: FoundCell,
        worldspace: Worldspace?
    ) -> EnvironmentBuild {
        let terrain = buildTerrain(found: found, worldspace: worldspace)
        let water = buildWater(found: found, worldspace: worldspace)
        return EnvironmentBuild(
            terrain: terrain,
            grass: buildGrass(
                found: found,
                worldspace: worldspace,
                terrain: terrain,
                waterHeight: water?.height
            ),
            water: water,
            sky: worldspace?.flags.contains(.noSky) == false ? SkyParameters() : nil
        )
    }

    /// Keeps only REFRs whose base resolves to DOOR and whose XTEL decoded.
    /// Interaction metadata independently includes non-teleport doors.
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

    /// Retains named use-key targets beside collision geometry. Every
    /// interaction-capable base uses the generic activation action except
    /// doors, whose typed open action can additionally drive XTEL.
    nonisolated func resolveInteractions(
        refs: [PlacedReference]
    ) -> [FormID: PlacedInteraction] {
        let modelBaseIndex = modelBaseIndexBuildingIfNeeded()
        var interactions: [FormID: PlacedInteraction] = [:]
        for ref in refs {
            guard
                let base = modelBaseIndex[ref.base.rawValue],
                base.allowsManualInteraction,
                let action = interactionAction(for: base.recordType)
            else { continue }
            let override = resolvedText(base.activateTextOverride)
                .flatMap { $0.isEmpty ? nil : $0 }
            let name = resolvedText(base.name)
                .flatMap { $0.isEmpty ? nil : $0 }
            let interaction = PlacedInteraction(
                reference: ref.formID,
                base: ref.base,
                position: ref.placement.position,
                name: name ?? base.editorID ?? base.formID.description,
                action: action,
                actionLabel: override ?? action.defaultLabel,
                sounds: base.sounds
            )
            interactions[ref.formID] = interaction
        }
        return interactions
    }

    nonisolated private func interactionAction(
        for recordType: FourCC
    ) -> InteractionAction? {
        switch recordType {
        case "DOOR":
            .open
        case "ACTI":
            .activate
        case "CONT":
            .search
        case "TREE":
            .harvest
        case "FURN":
            .use
        default:
            ModelBase.itemTypes.contains(recordType) ? .take : nil
        }
    }

    nonisolated private func resolvedText(_ text: LString?) -> String? {
        if case let .inline(value) = text {
            return value
        }
        return localizedStrings?.resolve(text)
    }

    /// The mesh + texture keys the cell just touched, drained so streaming
    /// unload can keep the union over resident cells and evict the rest.
    nonisolated func drainTouchedAssets() -> CellAssets {
        CellAssets(
            meshKeys: meshes.drainTouchedKeys()
                .union(collisionModels?.drainTouchedKeys() ?? []),
            textureKeys: textures.drainTouchedKeys()
        )
    }

    /// World AABB over everything the cell draws: placed models, actors,
    /// terrain and water. Nil when nothing drew.
    nonisolated private func unionedBounds(
        placements: [RenderPlacement],
        geometry: CellGeometryBuild
    ) -> ModelBounds? {
        var bounds: ModelBounds?
        let worlds = placements.compactMap(\.bounds)
            + [geometry.terrain?.bounds, geometry.water?.item.bounds].compactMap(\.self)
        for world in worlds {
            bounds = bounds.map { $0.union(world) } ?? world
        }
        return bounds
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
        let particles = makeParticlePlaybacks(instances: instances)
        let placed = instances.map { instance in
            RenderPlacement(
                model: instance.model,
                transform: instance.transform,
                bounds: meshes.bounds(forPath: instance.modelPath)?
                    .transformed(by: instance.transform)
            )
        }
        let bounds = unionedBounds(
            placements: placed + actors.placements, geometry: geometry
        )
        let renderScene = RenderScene(
            instances: placed + actors.placements,
            animations: actors.animations,
            terrain: geometry.terrain?.items ?? [],
            water: geometry.water.map { [$0.item] } ?? [],
            sky: found.cell.isInterior ? nil : geometry.sky,
            lighting: geometry.lighting,
            pointLights: geometry.pointLights,
            grass: geometry.grass?.renderPlacements ?? [],
            particles: particles
        )
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
            interactions: geometry.interactions,
            regions: found.cell.regions,
            acousticSpace: found.cell.acousticSpace,
            musicType: found.cell.musicType,
            worldspaceMusicType: geometry.worldspaceMusicType,
            terrainHeightField: geometry.terrain?.heightField,
            grassPlacements: geometry.grass?.placements ?? [],
            staticCollision: geometry.staticCollision,
            triggerVolumes: geometry.triggerVolumes,
            references: geometry.referenceIndex,
            stateSequence: geometry.stateSequence
        )
    }

    nonisolated private func makeParticlePlaybacks(
        instances: [ResolvedInstance]
    ) -> [ParticlePlayback] {
        var result: [ParticlePlayback] = []
        for instance in instances {
            do {
                result += try meshes.particlePlaybacks(
                    path: instance.modelPath,
                    placementTransform: instance.transform,
                    formID: instance.formID
                )
            } catch {
                let reason = String(describing: error)
                let source = instance.modelPath
                let message = "particle playback \(source) failed: \(reason)"
                Self.logger.warning("\(message, privacy: .public)")
            }
        }
        return result
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
            grassPlacementCount: geometry.grass?.placements.count ?? 0,
            grassTypeCount: geometry.grass?.typeCount ?? 0,
            grassTypeSkipCount: geometry.grass?.typeSkipCount ?? 0,
            waterPlaneCount: geometry.water == nil ? 0 : 1,
            pointLightCount: geometry.pointLights.count
        )
        summary.runtimeDisabledSkipCount = counts.runtimeDisabled
        summary.runtimeDeletedSkipCount = counts.runtimeDeleted
        summary.spawnedRefCount = counts.spawnedRefs
        summary.spawnedUnaddressableSkipCount = counts.unaddressableSpawns
        summary.actorCount = actors.counts.discovered
        summary.actorDrawnCount = actors.counts.rendered
        summary.actorDisabledSkipCount = actors.counts.disabledSkips
        summary.actorFailureCount = actors.counts.failures
        summary.actorFailureReasons = actors.counts.failureReasons
        summary.actorBuildDurationMS = actors.durationMS
        summary.actorAnimatedCount = actors.counts.animated
        summary.actorAnimationFailureCount = actors.counts.animationFailures
        summary.actorAnimationFailureReasons = actors.counts.animationFailureReasons
        summary.actorAppearanceSkipReasons = actors.counts.appearanceSkipReasons
        return summary
    }
}
