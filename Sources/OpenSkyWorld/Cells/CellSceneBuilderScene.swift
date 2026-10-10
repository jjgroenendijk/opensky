// Final CellScene assembly: placed models, environment draws, bounds, and one
// load summary.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorldInterface
import OpenSkyWorldState

nonisolated public struct CellGeometryBuild {
    public let location: CellSceneLocation
    public let doors: [PlacedDoor]
    public let interactions: [FormID: PlacedInteraction]
    public let terrain: TerrainBuild?
    public let grass: GrassBuild?
    public let water: WaterBuild?
    public let sky: SkyParameters?
    public let lighting: RenderLighting?
    public let pointLights: [RenderPointLight]
    public let staticCollision: StaticCollisionSet
    public var triggerVolumes: TriggerVolumeSet = .empty
    public var dynamicBodies: [DynamicBodyPlacement] = []
    /// Decoded NAVM records built beside the rest of the cell-owned geometry.
    public var navmeshes: [Navmesh] = []
    public let actors: CellActorBuild
    /// The cell's worldspace; the interior path has none and leaves it nil.
    public var world: FoundWorld?
    /// REFR entries only; actor entries travel inside `actors`.
    public var referenceEntries: [RuntimeReferenceEntry] = []
    /// The world-state snapshot sequence applied; 0 means none.
    public var stateSequence: UInt64 = 0
    /// References that ride a vehicle, drawn at their live pose like a body.
    public var vehicleFollowers: Set<UInt32> = []

    public var referenceIndex: RuntimeReferenceIndex {
        RuntimeReferenceIndex(
            entries: referenceEntries + actors.entries,
            absentActors: actors.disabledKeys
        )
    }
}

/// Exterior environment trio built beside the placed models.
nonisolated public struct EnvironmentBuild {
    public let terrain: TerrainBuild?
    public let grass: GrassBuild?
    public let water: WaterBuild?
    public let sky: SkyParameters?
}

nonisolated extension CellSceneBuilder {
    /// Terrain + water + procedural sky (suppressed for noSky worldspaces).
    nonisolated public func buildEnvironment(
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
    nonisolated public func resolveDoors(refs: [PlacedReference]) -> [PlacedDoor] {
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
    nonisolated public func resolveInteractions(
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
                sounds: base.sounds,
                voiceType: base.voiceType,
                station: base.workbench.map {
                    CraftingStation(workbench: $0, keywords: base.keywords.keywords)
                },
                produce: base.produce,
                lock: action == .open || action == .search ? ref.lock : nil
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
        case "TREE", "FLOR":
            .harvest
        case "TACT":
            .talk
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

    /// Every build path starts here, so `drainTouchedAssets` reports one cell's
    /// working set for streaming unload.
    nonisolated public func resetTouchedAssets() {
        _ = drainTouchedAssets()
    }

    nonisolated public func drainTouchedAssets() -> CellAssets {
        CellAssets(
            meshKeys: meshes.drainTouchedKeys()
                .union(collisionModels?.drainTouchedKeys() ?? []),
            textureKeys: textures.drainTouchedKeys()
        )
    }

    /// Nil when nothing drew.
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

    nonisolated public func makeScene(
        found: FoundCell,
        grid: (x: Int32, y: Int32),
        instances: [ResolvedInstance],
        geometry: CellGeometryBuild,
        counts: BuildCounts
    ) -> CellScene {
        let actors = geometry.actors
        let particles = makeParticlePlaybacks(instances: instances)
        // A simulated reference draws at its live pose, so it keeps its FormID.
        let simulated = Set(geometry.dynamicBodies.map(\.reference.rawValue))
            .union(geometry.vehicleFollowers)
        let placed = renderPlacements(instances, simulated: simulated)
        let objects = animatedObjects(instances)
        let bounds = unionedBounds(
            placements: placed + actors.placements, geometry: geometry
        )
        let renderScene = RenderScene(
            instances: placed + actors.placements,
            animations: actors.animations + objects.map(\.playback),
            terrain: geometry.terrain?.items ?? [],
            water: geometry.water.map { [$0.item] } ?? [],
            sky: found.cell.isInterior ? nil : geometry.sky,
            lighting: geometry.lighting,
            pointLights: geometry.pointLights,
            grass: geometry.grass?.renderPlacements ?? [],
            particles: particles,
            placedWaterLook: geometry.water?.item.look ?? .fallback
        )
        let summary = makeSummary(
            found: found,
            grid: grid,
            instanceCount: instances.count,
            geometry: geometry,
            counts: counts
        )
        Self.logger.info("\(summary.summaryLine, privacy: .public)")
        var scene = CellScene(
            renderScene: renderScene,
            summary: summary,
            bounds: bounds.map { (min: $0.min, max: $0.max) },
            location: geometry.location,
            doors: geometry.doors,
            interactions: geometry.interactions,
            regions: found.cell.regions,
            acousticSpace: found.cell.acousticSpace,
            musicType: found.cell.musicType,
            owner: RecordOwnership(cell: found.cell),
            locationLink: found.cell.location,
            ownerPluginName: pluginName,
            worldspaceMusicType: geometry.world?.worldspace?.musicType,
            worldspace: geometry.world?.formID,
            terrainHeightField: geometry.terrain?.heightField,
            waterHeight: geometry.water?.height,
            grassPlacements: geometry.grass?.placements ?? [],
            staticCollision: geometry.staticCollision,
            triggerVolumes: geometry.triggerVolumes,
            dynamicBodies: geometry.dynamicBodies,
            navmeshes: geometry.navmeshes,
            references: geometry.referenceIndex,
            stateSequence: geometry.stateSequence
        )
        scene.animatedObjects = objects.map(\.object)
        return scene
    }

    nonisolated private func renderPlacements(
        _ instances: [ResolvedInstance],
        simulated: Set<UInt32>
    ) -> [RenderPlacement] {
        instances.filter { !$0.model.meshes.isEmpty }.map { instance in
            RenderPlacement(
                model: instance.model,
                transform: instance.transform,
                bounds: meshes.bounds(forPath: instance.modelPath, surface: instance.surface)?
                    .transformed(by: instance.transform),
                referenceFormID: simulated.contains(instance.formID) ? instance.formID : 0
            )
        }
    }

    nonisolated private func makeParticlePlaybacks(
        instances: [ResolvedInstance]
    ) -> [ParticlePlayback] {
        var result: [ParticlePlayback] = []
        for instance in instances {
            do {
                result += try meshes.particlePlaybacks(
                    path: instance.modelPath,
                    surface: instance.surface,
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
        summary.disabledSkipCount = counts.baselineDisabled
        summary.unresolvedEnableParentCount = counts.unresolvedEnableParents
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
        summary.actorHeads = actors.counts.heads
        summary.skippedRecords = skippedRecords
        return summary
    }
}
