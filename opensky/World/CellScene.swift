// Cell scene build output (todo 2.7 scene build): the drawable RenderScene
// plus what the app layer needs around it — a load summary (one-line report,
// AGENTS.md robustness rule) and a world AABB for camera placement.

import Foundation
import simd

/// The library cache keys one cell touched: its mesh + texture working set.
/// Streaming unions these over resident cells to know what to keep when a cell
/// unloads (eviction — docs/engine/cell-streaming.md). Empty for cells built
/// without eviction tracking (tests) — an empty keep-set simply evicts more.
nonisolated struct CellAssets: Equatable {
    var meshKeys: Set<String> = []
    var textureKeys: Set<String> = []
}

/// Stable identity of one built cell. Exterior cells drive grid streaming;
/// interior cells are addressed by CELL FormID because they have no XCLC.
nonisolated enum CellSceneLocation: Equatable {
    case exterior(CellCoordinate)
    case interior(FormID)
}

/// Teleport-capable DOOR placement retained beside render data so main-thread
/// interaction can select a nearby door without touching plugin bytes.
nonisolated struct PlacedDoor: Equatable {
    let reference: FormID
    let position: SIMD3<Float>
    let destination: PlacedReference.TeleportDestination
}

/// One built exterior cell, ready to render.
nonisolated struct CellScene {
    let renderScene: RenderScene
    let summary: CellLoadSummary
    /// World-space AABB over every drawn instance — nil when nothing drew.
    /// Downstream camera placement frames this box.
    let bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?
    let location: CellSceneLocation?
    let doors: [PlacedDoor]
    /// CPU collision surface for exterior LAND/DNAM terrain. nil for
    /// interiors or cells with no drawable terrain.
    let terrainHeightField: TerrainHeightField?
    /// Immutable mesh collision + per-cell broadphase. Empty for cells built
    /// without a collision VFS (legacy synthetic tests).
    let staticCollision: StaticCollisionSet
    /// Mesh + texture cache keys this cell uses, for unload eviction.
    var assets = CellAssets()

    init(
        renderScene: RenderScene,
        summary: CellLoadSummary,
        bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?,
        location: CellSceneLocation? = nil,
        doors: [PlacedDoor] = [],
        terrainHeightField: TerrainHeightField? = nil,
        staticCollision: StaticCollisionSet = .empty,
        assets: CellAssets = CellAssets()
    ) {
        self.renderScene = renderScene
        self.summary = summary
        self.bounds = bounds
        self.location = location
        self.doors = doors
        self.terrainHeightField = terrainHeightField
        self.staticCollision = staticCollision
        self.assets = assets
    }
}

/// Load accounting for one cell build. Per-ref failures never abort the build
/// (AGENTS.md mod-quirk rule) — each lands in a skip bucket instead. Skip
/// taxonomy: docs/engine/cell-scene.md.
nonisolated struct CellLoadSummary: Equatable {
    /// Cell editor ID when present, else "cell <FormID>".
    let cellName: String
    let gridX: Int32
    let gridY: Int32
    /// Non-deleted REFR records seen in the cell's persistent + temporary
    /// children groups.
    let totalRefCount: Int
    let drawnRefCount: Int
    /// REFR whose base FormID resolves to neither the STAT nor the
    /// ModelBase (MSTT/TREE/FURN/ACTI/CONT/DOOR) index — an unsupported
    /// base type (NPC_, ACHR, ...) or a malformed base record.
    let unsupportedBaseSkipCount: Int
    /// Resolved base carries no MODL — editor marker, nothing to draw.
    let markerSkipCount: Int
    /// Mesh load failed: missing file, parse error, or empty model.
    let modelFailureSkipCount: Int
    /// The REFR record itself failed to decode.
    let malformedRefSkipCount: Int
    /// Distinct models loaded (MeshLibrary.loadedCount).
    let modelCount: Int
    /// Distinct texture paths loaded / unresolved (TextureLibrary counters).
    let textureCount: Int
    let missingTextureCount: Int
    /// Terrain sub-meshes drawn for the cell: one per painted, non-hidden
    /// quadrant (0-4), or the single fallback-plane mesh, else 0 (no terrain).
    var terrainQuadrantCount = 0
    /// ATXT splat layers drawn across all terrain quadrants.
    var terrainLayerCount = 0
    /// Splat layers dropped: unresolvable LTEX/TXST chain or over the
    /// 8-layer format cap (TerrainConstant.maxLayers).
    var terrainLayerSkipCount = 0
    /// Flat water planes drawn for this cell (0 or 1).
    var waterPlaneCount = 0
    /// Supported LIGH/XEMI placements available to forward draws.
    var pointLightCount = 0
    /// Non-deleted ACHRs owned by this cell (local + position-mapped
    /// worldspace-persistent). Buckets below must account for each exactly
    /// once (5.5 exact-accounting rule).
    var actorCount = 0
    var actorDrawnCount = 0
    /// Initially-disabled ACHRs — explicit intentional skip (no script state).
    var actorDisabledSkipCount = 0
    /// Malformed ACHR, unresolved template/visual chain, or no core geometry.
    var actorFailureCount = 0
    /// Wall time of the cell's actor collect+resolve+assemble phase.
    var actorBuildDurationMS = 0.0

    var skippedRefCount: Int {
        unsupportedBaseSkipCount + markerSkipCount + modelFailureSkipCount + malformedRefSkipCount
    }

    /// Every discovered actor landed in exactly one bucket.
    var actorAccountingIsExact: Bool {
        actorCount == actorDrawnCount + actorDisabledSkipCount + actorFailureCount
    }

    /// One-line load report (AGENTS.md bracket-tag style), e.g.
    /// "[INFO] WhiterunExterior06 (6,-2): 16 refs, 16 drawn, 0 skipped,
    /// 8 models, 24 textures (0 missing)". The parenthetical lists only
    /// non-zero skip reasons and disappears when nothing skipped.
    var summaryLine: String {
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
        let skipped = reasons.isEmpty
            ? "\(skippedRefCount) skipped"
            : "\(skippedRefCount) skipped (\(reasons.joined(separator: ", ")))"
        // Terrain clause appended only when present, so a cell without terrain
        // logs the same line as before terrain build existed.
        var terrain = terrainQuadrantCount > 0 ? ", \(terrainQuadrantCount) terrain quads" : ""
        if terrainLayerCount > 0 || terrainLayerSkipCount > 0 {
            let dropped = terrainLayerSkipCount > 0 ? ", \(terrainLayerSkipCount) dropped" : ""
            terrain += " (\(terrainLayerCount) splat layers\(dropped))"
        }
        if waterPlaneCount > 0 {
            terrain += ", water"
        }
        if pointLightCount > 0 {
            terrain += ", \(pointLightCount) point lights"
        }
        // Actor clause appended only for actor-bearing cells; the breakdown
        // makes the exact-accounting rule greppable per cell.
        if actorCount > 0 {
            var buckets = ["\(actorDrawnCount) drawn"]
            if actorDisabledSkipCount > 0 {
                buckets.append("\(actorDisabledSkipCount) disabled")
            }
            if actorFailureCount > 0 {
                buckets.append("\(actorFailureCount) failed")
            }
            terrain += ", \(actorCount) actors (\(buckets.joined(separator: ", ")))"
        }
        return "[INFO] \(cellName) (\(gridX),\(gridY)): \(totalRefCount) refs, "
            + "\(drawnRefCount) drawn, \(skipped), \(modelCount) models, "
            + "\(textureCount) textures (\(missingTextureCount) missing)\(terrain)"
    }
}
