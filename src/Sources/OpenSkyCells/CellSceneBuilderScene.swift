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

nonisolated extension CellSceneBuilder.CellSceneAssembler {
    /// Terrain + water + procedural sky (suppressed for noSky worldspaces).
    nonisolated func buildEnvironment(
        found: FoundCell,
        worldspace: Worldspace?
    ) -> EnvironmentBuild {
        let terrain = owner.terrainBuilder.buildTerrain(found: found, worldspace: worldspace)
        let water = owner.waterBuilder.buildWater(found: found, worldspace: worldspace)
        return EnvironmentBuild(
            terrain: terrain,
            grass: owner.terrainBuilder.grass.buildGrass(
                found: found,
                worldspace: worldspace,
                terrain: terrain,
                waterHeight: water?.height
            ),
            water: water,
            sky: worldspace?.flags.contains(.noSky) == false ? SkyParameters() : nil
        )
    }

    /// Every build path starts here, so `drainTouchedAssets` reports one cell's
    /// working set for streaming unload.
    nonisolated func resetTouchedAssets() {
        _ = renderParts.drainTouchedAssets()
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
            .hazards.animatedVehicles(&instances, followers: geometry.vehicleFollowers)
        let doors = owner.objectBuilder.animated.animatedDoors(&instances)
        var nodes = owner.objectBuilder.animated.animatedNodes(&instances)
        let objects = owner.objectBuilder.animated.animatedObjects(instances)
        let particles = renderParts.particlePlaybacks(instances: instances, nodes: &nodes)
        // A simulated reference draws at its live pose, so it keeps its FormID.
        let simulated = Set(geometry.dynamicBodies.map(\.reference.rawValue))
            .union(geometry.vehicleFollowers)
        let placed = renderParts.renderPlacements(instances, simulated: simulated)
        let bounds = renderParts
            .unionedBounds(placements: placed + geometry.actors.placements, geometry: geometry)
        let renderScene = RenderScene(
            instances: placed + geometry.actors.placements,
            animations: geometry.actors.animations + objects.map(\.playback)
                + vehicles.map(\.playback) + doors.map(\.playback) + nodes.map(\.playback),
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
        let summary = renderParts.makeSummary(
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
}

nonisolated extension CellSceneBuilder {
    var assembler: CellSceneBuilder.CellSceneAssembler {
        CellSceneBuilder.CellSceneAssembler(owner: self)
    }
}
