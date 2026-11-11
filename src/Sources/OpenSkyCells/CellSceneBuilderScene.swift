// Final CellScene assembly: placed models, environment draws, bounds, and one
// load summary.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyObjectAnimation
public import OpenSkyPhysics
public import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyTerrain
public import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

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
    /// An interior's rooms and portals, for occlusion culling.
    public var rooms: RoomPortalGraph?
    public var waterVolumes: WaterVolumeSet = .empty

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

nonisolated extension CellSceneAssembler {
    /// Terrain + water + procedural sky (suppressed for noSky worldspaces).
    nonisolated func buildEnvironment(
        found: FoundCell,
        worldspace: Worldspace?
    ) -> EnvironmentBuild {
        let terrain = owner.terrainBuilder.buildTerrain(found: found, worldspace: worldspace)
        let water = owner.waterBuilder.buildWater(found: found, worldspace: worldspace)
        return EnvironmentBuild(
            terrain: terrain,
            grass: owner.terrainBuilder.buildGrass(
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
        let modelBaseIndex = owner.recordIndex.modelBaseIndexBuildingIfNeeded()
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
        let modelBaseIndex = owner.recordIndex.modelBaseIndexBuildingIfNeeded()
        var interactions: [FormID: PlacedInteraction] = [:]
        for ref in refs {
            guard
                let base = modelBaseIndex[ref.base.rawValue],
                base.allowsManualInteraction || base.isAutomaticDoor,
                let action = interactionAction(for: base.recordType)
            else { continue }
            let override = resolvedText(base.activateTextOverride)
                .flatMap { $0.isEmpty ? nil : $0 }
            let name = resolvedText(base.name)
                .flatMap { $0.isEmpty ? nil : $0 }
            let seats = base.recordType == "FURN" ? owner.objectBuilder
                .seats(of: base, at: ref) : []
            // The game's verbs are string settings; `ActivationPrompt` lays them on at run time.
            let isBed = seats.contains { $0.animationType == FurnitureSeat.sleepAnimation }
            var interaction = PlacedInteraction(
                reference: ref.formID,
                base: ref.base,
                position: ref.placement.position,
                name: name ?? base.editorID ?? base.formID.description,
                action: action,
                actionLabel: override ?? (isBed ? "Sleep" : action.defaultLabel),
                sounds: base.sounds,
                voiceType: base.voiceType,
                station: base.workbench.map {
                    CraftingStation(workbench: $0, keywords: base.keywords.keywords)
                },
                produce: base.produce,
                lock: action == .open || action == .search ? ref.lock : nil
            )
            interaction.seats = seats
            interaction.hasLabelOverride = override != nil
            // XAPD: only an activate parent or a script may activate the reference.
            interaction.parentActivateOnly = ref.details.parentActivateOnly == true
            if base.isAutomaticDoor {
                let area = interaction.parentActivateOnly
                    ? nil : Self.automaticArea(of: base, at: ref)
                guard let area else { continue }
                interaction.automaticArea = area
            }
            interactions[ref.formID] = interaction
        }
        return interactions
    }

    /// An automatic door without bounds covers no space, so it is left out.
    nonisolated private static func automaticArea(
        of base: ModelBase, at ref: PlacedReference
    ) -> AutomaticDoorArea? {
        guard let bounds = base.details.bounds, !bounds.isEmpty else { return nil }
        let transform = MatrixMath.placement(
            position: ref.placement.position, rotation: ref.placement.rotation, scale: ref.scale
        )
        return AutomaticDoorArea(
            worldToLocal: transform.inverse,
            minimum: SIMD3<Float>(bounds.minimum),
            maximum: SIMD3<Float>(bounds.maximum)
        )
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
        return owner.localizedStrings?.resolve(text)
    }

    /// Every build path starts here, so `drainTouchedAssets` reports one cell's
    /// working set for streaming unload.
    nonisolated func resetTouchedAssets() {
        _ = drainTouchedAssets()
    }

    nonisolated func drainTouchedAssets() -> CellAssets {
        CellAssets(
            meshKeys: owner.meshes.drainTouchedKeys()
                .union(owner.collisionModels?.drainTouchedKeys() ?? []),
            textureKeys: owner.textures.drainTouchedKeys()
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

    /// The CELL's own identity, trespass and wait flags, and encounter zone.
    nonisolated static func applyCellRecord(
        _ found: FoundCell, geometry: CellGeometryBuild, to scene: inout CellScene
    ) {
        scene.cellFormID = FormID(found.formID)
        scene.waterVolumes = geometry.waterVolumes
        scene.trespass = CellTrespassFlags(
            isPublicArea: found.cell.flags.contains(.publicArea),
            isOffLimits: found.cell.isOffLimits
        )
        scene.forbidsWaiting = found.cell.isNoWait
            || geometry.world?.worldspace?.isNoWait == true
        scene.encounterZone = encounterZone(of: found, in: geometry)
    }

    /// A cell without its own `XEZN` takes the worldspace's encounter zone.
    nonisolated static func encounterZone(of found: FoundCell, in geometry: CellGeometryBuild)
        -> FormID?
    {
        found.cell.encounterZone ?? geometry.world?.worldspace?.encounterZone
    }

    nonisolated func makeScene(
        cell: (found: FoundCell, grid: (x: Int32, y: Int32)),
        instances: [ResolvedInstance],
        geometry: CellGeometryBuild,
        counts: BuildCounts
    ) -> CellScene {
        var instances = instances + owner.objectBuilder.addOnInstances(for: instances)
        let vehicles = owner.objectBuilder
            .animatedVehicles(&instances, followers: geometry.vehicleFollowers)
        let doors = owner.objectBuilder.animatedDoors(&instances)
        var nodes = owner.objectBuilder.animatedNodes(&instances)
        let objects = owner.objectBuilder.animatedObjects(instances)
        let actors = geometry.actors
        let particles = particlePlaybacks(instances: instances, nodes: &nodes)
        // A simulated reference draws at its live pose, so it keeps its FormID.
        let simulated = Set(geometry.dynamicBodies.map(\.reference.rawValue))
            .union(geometry.vehicleFollowers)
        let placed = renderPlacements(instances, simulated: simulated)
        let bounds = unionedBounds(placements: placed + actors.placements, geometry: geometry)
        let renderScene = RenderScene(
            instances: placed + actors.placements,
            animations: actors.animations + objects.map(\.playback) + vehicles.map(\.playback)
                + doors.map(\.playback) + nodes.map(\.playback),
            terrain: geometry.terrain?.items ?? [],
            water: geometry.water.map { [$0.item] } ?? [],
            sky: cell.found.cell.isInterior ? nil : geometry.sky,
            lighting: geometry.lighting,
            pointLights: geometry.pointLights,
            grass: geometry.grass?.renderPlacements ?? [],
            particles: particles,
            placedWaterLook: geometry.water?.item.look ?? .fallback,
            rooms: geometry.rooms
        )
        let summary = makeSummary(
            cell: cell, instanceCount: instances.count, geometry: geometry, counts: counts
        )
        var scene = CellScene(
            renderScene: renderScene,
            summary: summary,
            bounds: bounds.map { (min: $0.min, max: $0.max) },
            location: geometry.location,
            doors: geometry.doors,
            interactions: geometry.interactions,
            regions: cell.found.cell.regions,
            acousticSpace: cell.found.cell.acousticSpace,
            musicType: cell.found.cell.musicType,
            owner: RecordOwnership(cell: cell.found.cell),
            locationLink: cell.found.cell.location,
            ownerPluginName: owner.pluginName,
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
        Self.applyCellRecord(cell.found, geometry: geometry, to: &scene)
        scene.animatedObjects = objects.map(\.object)
        scene.animatedVehicles = vehicles.map(\.vehicle)
        scene.sequenceDoors = doors.map(\.door)
        scene.nodeAnimations = nodes.map(\.mesh)
        return scene
    }

    /// Every particle system of the cell; a node animation keeps its own reference's.
    nonisolated private func particlePlaybacks(
        instances: [ResolvedInstance], nodes: inout [(
            mesh: CellNodeAnimation,
            playback: any RenderAnimation
        )]
    ) -> [ParticlePlayback] {
        let particlesByReference = makeParticlePlaybacks(instances: instances)
        let byReference = Dictionary(
            particlesByReference.map { ($0.reference, $0.playbacks) },
            uniquingKeysWith: +
        )
        for index in nodes.indices {
            nodes[index].mesh.particles = byReference[nodes[index].mesh.reference] ?? []
        }
        return particlesByReference.flatMap(\.playbacks)
    }

    nonisolated private func renderPlacements(
        _ instances: [ResolvedInstance],
        simulated: Set<UInt32>
    ) -> [RenderPlacement] {
        instances.filter { !$0.model.meshes.isEmpty }.map { instance in
            var placement = RenderPlacement(
                model: instance.model,
                transform: instance.transform,
                bounds: owner.meshes.bounds(forPath: instance.modelPath, surface: instance.surface)?
                    .transformed(by: instance.transform),
                referenceFormID: simulated.contains(instance.formID) ? instance.formID : 0
            )
            placement.emittance = instance.emittance
            placement.treeMotion = instance.treeMotion
            return placement
        }
    }

    nonisolated private func makeParticlePlaybacks(
        instances: [ResolvedInstance]
    ) -> [(reference: UInt32, playbacks: [ParticlePlayback])] {
        var result: [(reference: UInt32, playbacks: [ParticlePlayback])] = []
        for instance in instances {
            do {
                try result.append((instance.formID, owner.meshes.particlePlaybacks(
                    path: instance.modelPath,
                    surface: instance.surface,
                    placementTransform: instance.transform,
                    formID: instance.formID,
                    emittance: instance.emittance
                )))
            } catch {
                let reason = String(describing: error)
                let source = instance.modelPath
                let message = "particle playback \(source) failed: \(reason)"
                CellSceneBuilder.logger.warning("\(message, privacy: .public)")
            }
        }
        return result
    }

    nonisolated private func makeSummary(
        cell: (found: FoundCell, grid: (x: Int32, y: Int32)),
        instanceCount: Int,
        geometry: CellGeometryBuild,
        counts: BuildCounts
    ) -> CellLoadSummary {
        let (found, grid) = cell
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
            modelCount: owner.meshes.loadedCount,
            textureCount: owner.textures.loadedCount,
            missingTextureCount: owner.textures.missingCount,
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
        summary.skippedRecords = owner.skippedRecords
        CellSceneBuilder.logger.info("\(summary.summaryLine, privacy: .public)")
        return summary
    }
}

nonisolated extension CellSceneBuilder {
    var assembler: CellSceneAssembler {
        CellSceneAssembler(owner: self)
    }
}
