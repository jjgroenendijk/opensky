// Cell scene build output: the drawable RenderScene plus a load summary and a
// world AABB for camera placement.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyShaderTypes
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// The mesh and texture keys one cell touched. Streaming keeps the union over
/// resident cells on unload (docs/engine/cell-streaming.md).
nonisolated public struct CellAssets: Equatable, Sendable {
    public var meshKeys: Set<String> = []
    public var textureKeys: Set<String> = []

    public init(meshKeys: Set<String> = [], textureKeys: Set<String> = []) {
        self.meshKeys = meshKeys
        self.textureKeys = textureKeys
    }
}

/// Teleport-capable DOOR placement retained beside render data so main-thread
/// interaction can select a nearby door without touching plugin bytes.
nonisolated public struct PlacedDoor: Equatable, Sendable {
    public let reference: FormID
    public let position: SIMD3<Float>
    public let destination: PlacedReference.TeleportDestination
}

/// One built exterior cell, ready to render.
nonisolated public struct CellScene: Sendable {
    public let renderScene: RenderScene
    public let summary: CellLoadSummary
    /// World-space AABB over every drawn instance — nil when nothing drew.
    /// Downstream camera placement frames this box.
    public let bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?
    public let location: CellSceneLocation?
    public let doors: [PlacedDoor]
    /// REFR -> resolved record text/action for view-ray interaction.
    public let interactions: [FormID: PlacedInteraction]
    /// XCLR regions; the streamer feeds the center cell's set to the weather runtime.
    public let regions: [FormID]
    /// XCAS acoustic space for interior ambience; nil when the cell names none.
    public let acousticSpace: FormID?
    /// XCMO music override; the first link in the music precedence chain.
    public let musicType: FormID?
    /// CELL `XOWN`/`XRNK`. An unowned reference here inherits it; trespass uses it.
    public let owner: RecordOwnership?
    /// CELL `XLCN`, unresolved: `CrimeFactionResolver` walks it with the
    /// load-order stores the builder does not hold.
    public let locationLink: FormID?
    /// The plugin `owner` and `locationLink` are spelled against, which is the
    /// plugin the cell record was read from.
    public let ownerPluginName: String?
    /// The worldspace ZNAM music type; the last link in the chain.
    public let worldspaceMusicType: FormID?
    /// The WRLD's load-order FormID, which a location's `LCEC` cell list names. Nil indoors.
    public let worldspace: FormID?

    public var isInterior: Bool {
        if case .interior = location {
            return true
        }
        return false
    }

    /// CPU collision surface for exterior LAND/DNAM terrain. nil for
    /// interiors or cells with no drawable terrain.
    public let terrainHeightField: TerrainHeightField?
    /// CELL XCLW over the worldspace default, like the drawn plane. Vanilla
    /// authors one plane per cell.
    public let waterHeight: Float?
    /// Deterministic cell-owned CPU instances retained for inspection +
    /// accounting; matching GPU grass batches live in renderScene.
    public let grassPlacements: [GrassPlacement]
    /// Immutable mesh collision + per-cell broadphase. Empty for cells built
    /// without a collision VFS (legacy synthetic tests).
    public let staticCollision: StaticCollisionSet
    /// SkyrimLayer 12 NIF bodies plus `XPRM` boxes and spheres, over the same
    /// broadphase as the solid set.
    public let triggerVolumes: TriggerVolumeSet
    /// Posed movable clutter. Empty without reference retention, because a body
    /// registers under a `ReferenceKey`.
    public let dynamicBodies: [DynamicBodyPlacement]
    /// Walkable surfaces the streamer adds to and removes from its navigation graph.
    public let navmeshes: [Navmesh]
    /// REFR/ACHR records by `ReferenceKey` and by raw FormID.
    public let references: RuntimeReferenceIndex
    /// The `WorldStateSnapshot` sequence this cell was built from; 0 means none.
    /// The streamer compares it with the store to spot a stale scene.
    public let stateSequence: UInt64
    /// Mesh + texture cache keys this cell uses, for unload eviction.
    public var assets = CellAssets()
    /// Enabled `PHZD` placed hazards, for the hazard runtime.
    public var hazards: [CellHazard] = []
    /// CELL `XCIM`, the interior's image space, spelled in `ownerPluginName`.
    public var imageSpace: FormID?

    public init(
        renderScene: RenderScene,
        summary: CellLoadSummary,
        bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?,
        location: CellSceneLocation? = nil,
        doors: [PlacedDoor] = [],
        interactions: [FormID: PlacedInteraction] = [:],
        regions: [FormID] = [],
        acousticSpace: FormID? = nil,
        musicType: FormID? = nil,
        owner: RecordOwnership? = nil,
        locationLink: FormID? = nil,
        ownerPluginName: String? = nil,
        worldspaceMusicType: FormID? = nil,
        worldspace: FormID? = nil,
        terrainHeightField: TerrainHeightField? = nil,
        waterHeight: Float? = nil,
        grassPlacements: [GrassPlacement] = [],
        staticCollision: StaticCollisionSet = .empty,
        triggerVolumes: TriggerVolumeSet = .empty,
        dynamicBodies: [DynamicBodyPlacement] = [],
        navmeshes: [Navmesh] = [],
        references: RuntimeReferenceIndex = .empty,
        stateSequence: UInt64 = 0,
        assets: CellAssets = CellAssets()
    ) {
        self.renderScene = renderScene
        self.summary = summary
        self.bounds = bounds
        self.location = location
        self.doors = doors
        self.interactions = interactions
        self.regions = regions
        self.acousticSpace = acousticSpace
        self.musicType = musicType
        self.owner = owner
        self.locationLink = locationLink
        self.ownerPluginName = ownerPluginName
        self.worldspaceMusicType = worldspaceMusicType
        self.worldspace = worldspace
        self.terrainHeightField = terrainHeightField
        self.waterHeight = waterHeight
        self.grassPlacements = grassPlacements
        self.staticCollision = staticCollision
        self.triggerVolumes = triggerVolumes
        self.dynamicBodies = dynamicBodies
        self.navmeshes = navmeshes
        self.references = references
        self.stateSequence = stateSequence
        self.assets = assets
    }
}

/// Load accounting for one cell build. A bad reference lands in a skip bucket
/// and never aborts the build (docs/engine/cell-scene.md).
nonisolated public struct CellLoadSummary: Equatable, Sendable {
    /// Cell editor ID when present, else "cell <FormID>".
    public let cellName: String
    public let gridX: Int32
    public let gridY: Int32
    /// Non-deleted REFRs in the persistent and temporary children groups.
    public let totalRefCount: Int
    public let drawnRefCount: Int
    /// The base is in neither the STAT nor the ModelBase index.
    public let unsupportedBaseSkipCount: Int
    /// Resolved base carries no MODL — editor marker, nothing to draw.
    public let markerSkipCount: Int
    /// Mesh load failed: missing file, parse error, or empty model.
    public let modelFailureSkipCount: Int
    /// The REFR record itself failed to decode.
    public let malformedRefSkipCount: Int
    /// Distinct models loaded (MeshLibrary.loadedCount).
    public let modelCount: Int
    /// Distinct texture paths loaded / unresolved (TextureLibrary counters).
    public let textureCount: Int
    public let missingTextureCount: Int
    /// One per painted, visible quadrant (0-4), or 1 for the fallback plane.
    public var terrainQuadrantCount = 0
    /// ATXT splat layers drawn across all terrain quadrants.
    public var terrainLayerCount = 0
    /// A broken LTEX/TXST chain, or over `TerrainConstant.maxLayers`.
    public var terrainLayerSkipCount = 0
    /// Procedural GRAS instances/types retained by this cell.
    public var grassPlacementCount = 0
    public var grassTypeCount = 0
    /// LTEX GNAM references with no usable GRAS DATA/MODL record.
    public var grassTypeSkipCount = 0
    /// Flat water planes drawn for this cell (0 or 1).
    public var waterPlaneCount = 0
    /// Supported LIGH/XEMI placements available to forward draws.
    public var pointLightCount = 0
    /// Disabled at runtime; skipped like an initially-disabled record.
    public var runtimeDisabledSkipCount = 0
    /// Deleted at runtime. The header `deleted` flag is filtered before counting.
    public var runtimeDeletedSkipCount = 0
    /// Initially disabled, or held off by a disabled enable parent.
    public var disabledSkipCount = 0
    /// `XESP` links whose parent was outside the build. Not a skip bucket.
    public var unresolvedEnableParentCount = 0
    /// Objects the game placed here. Outside `totalRefCount`, inside `drawnRefCount`:
    /// `totalRefCount + spawnedRefCount == drawnRefCount + skippedRefCount`.
    public var spawnedRefCount = 0
    /// Spawns past the 24-bit object ID space; counted so the identity holds.
    public var spawnedUnaddressableSkipCount = 0
    /// Local and position-mapped persistent ACHRs; each lands in one bucket below.
    public var actorCount = 0
    public var actorDrawnCount = 0
    /// Initially-disabled ACHRs — explicit intentional skip (no script state).
    public var actorDisabledSkipCount = 0
    /// Malformed ACHR, unresolved template/visual chain, or no core geometry.
    public var actorFailureCount = 0
    /// One "ACHR <id>: <why>" per counted failure.
    public var actorFailureReasons: [String] = []
    /// Wall time of the cell's actor collect+resolve+assemble phase.
    public var actorBuildDurationMS = 0.0
    /// Rendered actors split into live idle playback + reason-tagged static fallback.
    public var actorAnimatedCount = 0
    public var actorAnimationFailureCount = 0
    public var actorAnimationFailureReasons: [String] = []
    /// "ACHR <id>: <reason> (<subject>)". Not failures, so outside the identities;
    /// read by the `World > Inventory & Equipment` inspection.
    public var actorAppearanceSkipReasons: [String] = []
    /// What each drawn humanoid's head is built from, by ACHR.
    public var actorHeads: [FormID: ActorHeadReadout] = [:]
    /// Records the builder could not decode so far, outside the reference buckets.
    public var skippedRecords = SkippedRecords()

    public var skippedRefCount: Int {
        unsupportedBaseSkipCount + markerSkipCount + modelFailureSkipCount
            + malformedRefSkipCount + runtimeDisabledSkipCount + runtimeDeletedSkipCount
            + disabledSkipCount + spawnedUnaddressableSkipCount
    }

    /// Every reference the build saw — authored or spawned — landed in exactly
    /// one bucket, drawn or skipped.
    public var referenceAccountingIsExact: Bool {
        totalRefCount + spawnedRefCount == drawnRefCount + skippedRefCount
    }

    /// Every discovered actor landed in exactly one bucket.
    public var actorAccountingIsExact: Bool {
        actorCount == actorDrawnCount + actorDisabledSkipCount + actorFailureCount
    }

    /// Every counted actor failure carries a reason (5.6 zero-unexplained rule).
    public var actorFailuresAreExplained: Bool {
        actorFailureCount == actorFailureReasons.count
    }

    public var actorAnimationAccountingIsExact: Bool {
        actorDrawnCount == actorAnimatedCount + actorAnimationFailureCount
    }

    public var actorAnimationFailuresAreExplained: Bool {
        actorAnimationFailureCount == actorAnimationFailureReasons.count
    }

    /// For example "[INFO] WhiterunExterior06 (6,-2): 16 refs, 16 drawn, 0 skipped,
    /// 8 models, 24 textures (0 missing)". Only non-zero skip reasons are listed.
    public var summaryLine: String {
        var reasons: [String] = []
        if unsupportedBaseSkipCount > 0 {
            reasons.append("\(unsupportedBaseSkipCount) unsupported-base")
        }
        if markerSkipCount > 0 {
            reasons.append("\(markerSkipCount) marker")
        }
        if modelFailureSkipCount > 0 {
            reasons.append("\(modelFailureSkipCount) load-failed")
        }
        if malformedRefSkipCount > 0 {
            reasons.append("\(malformedRefSkipCount) malformed")
        }
        if runtimeDisabledSkipCount > 0 {
            reasons.append("\(runtimeDisabledSkipCount) runtime-disabled")
        }
        if runtimeDeletedSkipCount > 0 {
            reasons.append("\(runtimeDeletedSkipCount) runtime-deleted")
        }
        if disabledSkipCount > 0 {
            reasons.append("\(disabledSkipCount) disabled")
        }
        if spawnedUnaddressableSkipCount > 0 {
            reasons.append("\(spawnedUnaddressableSkipCount) spawn-unaddressable")
        }
        let skipped = reasons.isEmpty
            ? "\(skippedRefCount) skipped"
            : "\(skippedRefCount) skipped (\(reasons.joined(separator: ", ")))"
        var terrain = terrainQuadrantCount > 0 ? ", \(terrainQuadrantCount) terrain quads" : ""
        if terrainLayerCount > 0 || terrainLayerSkipCount > 0 {
            let dropped = terrainLayerSkipCount > 0 ? ", \(terrainLayerSkipCount) dropped" : ""
            terrain += " (\(terrainLayerCount) splat layers\(dropped))"
        }
        if waterPlaneCount > 0 {
            terrain += ", water"
        }
        if grassTypeCount > 0 || grassTypeSkipCount > 0 {
            let dropped = grassTypeSkipCount > 0 ? ", \(grassTypeSkipCount) dropped" : ""
            terrain += ", \(grassPlacementCount) grass placements "
                + "(\(grassTypeCount) types\(dropped))"
        }
        if pointLightCount > 0 {
            terrain += ", \(pointLightCount) point lights"
        }
        if actorCount > 0 {
            var buckets = ["\(actorDrawnCount) drawn"]
            if actorDisabledSkipCount > 0 {
                buckets.append("\(actorDisabledSkipCount) disabled")
            }
            if actorFailureCount > 0 {
                buckets.append("\(actorFailureCount) failed")
            }
            terrain += ", \(actorCount) actors (\(buckets.joined(separator: ", ")))"
            terrain += ", \(actorAnimatedCount) animated"
            if actorAnimationFailureCount > 0 {
                terrain += ", \(actorAnimationFailureCount) static"
            }
        }
        if !skippedRecords.isEmpty {
            terrain += ", \(skippedRecords.total) malformed records"
        }
        return "[INFO] \(cellName) (\(gridX),\(gridY)): \(totalRefCount) refs, "
            + "\(drawnRefCount) drawn, \(skipped), \(modelCount) models, "
            + "\(textureCount) textures (\(missingTextureCount) missing)\(terrain)"
    }
}
