// Cell scene build (todo 2.7 scene build, widened to MSTT/TREE/FURN/ACTI/CONT
// bases in 3.2): walk one plugin's WRLD tree to an exterior cell, resolve
// each REFR's base object, load its NIF via MeshLibrary, and emit an
// instancing-ready RenderScene. Structural failures (worldspace or cell
// absent) throw; per-ref and per-asset failures log + skip + count and never
// abort the build (AGENTS.md mod-quirk rule).
//
// Group nesting: WRLD top group -> WRLD record + world-children group ->
// exterior block/sub-block groups -> CELL record + cell-children group ->
// persistent/temporary children groups -> REFR records. Reference: UESP
// "Skyrim Mod:Mod File Format" — Groups. Walk order + skip taxonomy:
// docs/engine/cell-scene.md.

import Foundation
import Metal
import OSLog
import simd

nonisolated enum CellSceneError: Error, Equatable {
    /// No WRLD record carries the requested editor ID.
    case worldspaceNotFound(editorID: String)
    /// The worldspace holds no CELL at the requested grid slot.
    case cellNotFound(worldspaceEditorID: String, gridX: Int32, gridY: Int32)
}

/// Per-build skip accounting; folded into CellLoadSummary at the end.
nonisolated private struct BuildCounts {
    var totalRefs = 0
    var malformedRefs = 0
    var unsupportedBases = 0
    var markers = 0
    var modelFailures = 0
}

/// One base record resolved to its drawable model path, regardless of
/// whether it came from the STAT or ModelBase (MSTT/TREE/FURN/ACTI/CONT)
/// index — resolveInstances treats both the same past this point.
nonisolated private struct ResolvedBase {
    let formID: FormID
    let recordType: FourCC
    /// Nil = marker base (no MODL), nothing to draw.
    let modelPath: String?
}

/// One resolved placement, sortable into instancing-ready order.
nonisolated private struct ResolvedInstance {
    /// Normalized mesh path — primary grouping key.
    let sortKey: String
    /// REFR FormID — deterministic tie-break within one model.
    let formID: UInt32
    /// Raw MODL path, for the bounds lookup in MeshLibrary.
    let modelPath: String
    let model: RenderModel
    let transform: float4x4
}

/// A located CELL record plus the cell-children group that follows it
/// (nil children = cell without references). Internal: the terrain half of
/// the build (CellSceneBuilderTerrain.swift) consumes it cross-file.
nonisolated struct FoundCell {
    let cell: Cell
    let formID: UInt32
    let children: ESMGroup?
}

/// The world-children group plus the decoded WRLD it belongs to (DNAM default
/// land height feeds the LAND-less terrain fallback).
nonisolated private struct FoundWorld {
    let children: ESMGroup
    let worldspace: Worldspace?
}

/// Builds a CellScene from a plugin + asset libraries. Class (not struct)
/// because the STAT index is cached across builds. Single-threaded like the
/// libraries it drives: scene build runs once at startup.
nonisolated final class CellSceneBuilder {
    /// Members below stay internal (not private) where
    /// CellSceneBuilderTerrain.swift extends the build cross-file; the
    /// module boundary still hides them from callers.
    static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "CellScene"
    )

    let file: ESMFile
    let meshes: MeshLibrary
    let textures: TextureLibrary
    /// FormID -> STAT over the STAT top group, built on first use.
    private var statIndex: [UInt32: StaticObject]?
    /// FormID -> ModelBase over the MSTT/TREE/FURN/ACTI/CONT top groups,
    /// built on first use. Checked when a ref's base is not a STAT.
    private var modelBaseIndex: [UInt32: ModelBase]?

    init(file: ESMFile, meshes: MeshLibrary, textures: TextureLibrary) {
        self.file = file
        self.meshes = meshes
        self.textures = textures
    }

    func buildScene(
        worldspaceEditorID: String,
        gridX: Int32,
        gridY: Int32
    ) throws -> CellScene {
        // localized only affects FULL lstrings, which scene build never
        // reads — a failed TES4 decode safely defaults to false.
        // Clear any stale working set so this build's touched keys are exactly
        // this cell's mesh + texture set (recorded onto the CellScene for
        // unload eviction — docs/engine/cell-streaming.md).
        _ = meshes.drainTouchedKeys()
        _ = textures.drainTouchedKeys()
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        let world = try worldChildrenGroup(editorID: worldspaceEditorID, localized: localized)
        guard
            let found = findCell(
                in: world.children, gridX: gridX, gridY: gridY, localized: localized
            )
        else {
            throw CellSceneError.cellNotFound(
                worldspaceEditorID: worldspaceEditorID,
                gridX: gridX,
                gridY: gridY
            )
        }
        var counts = BuildCounts()
        let refs = collectReferences(in: found.children, counts: &counts)
        let instances = resolveInstances(refs: refs, counts: &counts)
        let terrain = buildTerrain(found: found, worldspace: world.worldspace)
        var scene = makeScene(
            found: found,
            grid: (x: gridX, y: gridY),
            instances: instances,
            terrain: terrain,
            counts: counts
        )
        // Record the mesh + texture keys this cell touched so streaming unload
        // can keep the union over resident cells and evict the rest.
        scene.assets = CellAssets(
            meshKeys: meshes.drainTouchedKeys(),
            textureKeys: textures.drainTouchedKeys()
        )
        return scene
    }
}

extension CellSceneBuilder {
    /// The WRLD top group interleaves WRLD records with world-children groups
    /// labeled by the owning record's FormID. EDID match is exact (editor IDs
    /// are stable identifiers). A malformed WRLD is skipped — another
    /// worldspace may still match.
    nonisolated private func worldChildrenGroup(
        editorID: String,
        localized: Bool
    ) throws -> FoundWorld {
        guard let top = file.topGroup(of: "WRLD") else {
            throw CellSceneError.worldspaceNotFound(editorID: editorID)
        }
        var matchedFormID: UInt32?
        var matchedWorld: Worldspace?
        for child in try top.children() {
            switch child {
            case let .record(record) where record.type == "WRLD":
                guard let world = try? Worldspace(record: record, localized: localized) else {
                    let id = FormID(record.formID).description
                    Self.logger.warning("malformed WRLD \(id, privacy: .public) skipped")
                    continue
                }
                let matches = world.editorID == editorID
                matchedFormID = matches ? record.formID : nil
                matchedWorld = matches ? world : nil
            case let .group(group)
                where group.kind == .worldChildren && group.parentFormID == matchedFormID:
                return FoundWorld(children: group, worldspace: matchedWorld)
            default:
                break
            }
        }
        throw CellSceneError.worldspaceNotFound(editorID: editorID)
    }

    /// Depth-first over exterior block/sub-block groups. Match is by decoded
    /// XCLC grid, never by block labels (unreliable in CK-ignored groups —
    /// see ESMGroup).
    nonisolated private func findCell(
        in group: ESMGroup,
        gridX: Int32,
        gridY: Int32,
        localized: Bool
    ) -> FoundCell? {
        // Malformed subtree -> log + prune instead of aborting: the target
        // cell may live in a sibling block (mod-quirk rule).
        guard let children = try? group.children() else {
            Self.logger.warning("malformed group under WRLD tree skipped")
            return nil
        }
        for (index, child) in children.enumerated() {
            switch child {
            case let .record(record) where record.type == "CELL":
                guard
                    let cell = try? Cell(record: record, localized: localized),
                    let grid = cell.grid, grid.x == gridX, grid.y == gridY
                else { continue }
                return FoundCell(
                    cell: cell,
                    formID: record.formID,
                    children: cellChildrenGroup(
                        following: index, in: children, cellFormID: record.formID
                    )
                )
            case let .group(sub)
                where sub.kind == .exteriorCellBlock || sub.kind == .exteriorCellSubBlock:
                let found = findCell(in: sub, gridX: gridX, gridY: gridY, localized: localized)
                if let found {
                    return found
                }
            default:
                break
            }
        }
        return nil
    }

    /// The cell-children group for a CELL record sits after it among the same
    /// siblings, labeled with the cell's FormID.
    nonisolated private func cellChildrenGroup(
        following index: Int,
        in children: [ESMGroup.Child],
        cellFormID: UInt32
    ) -> ESMGroup? {
        let rest = children[(index + 1)...]
        for case let .group(group) in rest where group.kind == .cellChildren {
            if group.parentFormID == cellFormID {
                return group
            }
        }
        return nil
    }

    /// REFR records from the cell's persistent + temporary children groups.
    /// LAND is handled separately (buildTerrain); other non-REFR types (NAVM,
    /// ACHR, PGRE, ...) are not static placements — ignored deliberately and
    /// not counted (skip taxonomy, docs/engine/cell-scene.md). Deleted REFRs
    /// place nothing -> also ignored. A REFR that fails to decode is malformed.
    nonisolated private func collectReferences(
        in cellChildren: ESMGroup?,
        counts: inout BuildCounts
    ) -> [PlacedReference] {
        guard let cellChildren, let children = try? cellChildren.children() else {
            if cellChildren != nil {
                Self.logger.warning("malformed cell-children group skipped")
            }
            return []
        }
        var refs: [PlacedReference] = []
        for case let .group(group) in children {
            guard
                group.kind == .cellPersistentChildren || group.kind == .cellTemporaryChildren,
                let records = try? group.children()
            else { continue }
            for case let .record(record) in records where record.type == "REFR" {
                guard !record.isDeleted else { continue }
                counts.totalRefs += 1
                do {
                    try refs.append(PlacedReference(record: record))
                } catch {
                    counts.malformedRefs += 1
                    let id = FormID(record.formID).description
                    Self.logger.warning("malformed REFR \(id, privacy: .public) skipped")
                }
            }
        }
        return refs
    }

    /// Resolves refs to placed instances. Skip buckets: base FormID resolves
    /// to neither the STAT nor the ModelBase (MSTT/TREE/FURN/ACTI/CONT)
    /// index -> unsupported base; a resolved base without MODL -> marker;
    /// mesh load error -> model failure. Output is sorted by (normalized
    /// mesh path, FormID) so instances sharing a RenderModel are adjacent
    /// (instancing-ready) and the order is deterministic across runs.
    nonisolated private func resolveInstances(
        refs: [PlacedReference],
        counts: inout BuildCounts
    ) -> [ResolvedInstance] {
        guard !refs.isEmpty else { return [] }
        let statIndex = statIndexBuildingIfNeeded()
        let modelBaseIndex = modelBaseIndexBuildingIfNeeded()
        var instances: [ResolvedInstance] = []
        for ref in refs {
            let id = ref.formID.description
            guard
                let resolved = resolveBase(
                    formID: ref.base.rawValue, statIndex: statIndex, modelBaseIndex: modelBaseIndex
                )
            else {
                counts.unsupportedBases += 1
                let base = ref.base.description
                Self.logger.info(
                    """
                    REFR \(id, privacy: .public): base \(base, privacy: .public) \
                    type not supported, skipped
                    """
                )
                continue
            }
            guard let modelPath = resolved.modelPath else {
                counts.markers += 1
                let base = resolved.formID.description
                let type = resolved.recordType.description
                Self.logger.info(
                    """
                    REFR \(id, privacy: .public): marker \(type, privacy: .public) \
                    \(base, privacy: .public), skipped
                    """
                )
                continue
            }
            do {
                let model = try meshes.model(path: modelPath)
                instances.append(ResolvedInstance(
                    sortKey: (try? VirtualFileSystem.normalize(modelPath)) ?? modelPath,
                    formID: ref.formID.rawValue,
                    modelPath: modelPath,
                    model: model,
                    transform: MatrixMath.placement(
                        position: ref.placement.position,
                        rotation: ref.placement.rotation,
                        scale: ref.scale
                    )
                ))
            } catch {
                counts.modelFailures += 1
                let reason = String(describing: error)
                Self.logger.warning(
                    """
                    REFR \(id, privacy: .public): model \(modelPath, privacy: .public) \
                    failed (\(reason, privacy: .public)), skipped
                    """
                )
            }
        }
        return instances.sorted { ($0.sortKey, $0.formID) < ($1.sortKey, $1.formID) }
    }

    /// FormID -> StaticObject over the STAT top group. Raw FormIDs suffice
    /// for now: scene build reads a single plugin, so REFR base IDs and STAT
    /// record IDs share one FormID space (cross-plugin resolution via
    /// FormIDResolver arrives with load-order support). Malformed STATs are
    /// skipped — refs pointing at them fall into the unsupported-base bucket.
    nonisolated private func statIndexBuildingIfNeeded() -> [UInt32: StaticObject] {
        if let statIndex {
            return statIndex
        }
        var index: [UInt32: StaticObject] = [:]
        if let top = file.topGroup(of: "STAT"), let children = try? top.children() {
            for case let .record(record) in children where record.type == "STAT" {
                guard let stat = try? StaticObject(record: record) else {
                    let id = FormID(record.formID).description
                    Self.logger.warning("malformed STAT \(id, privacy: .public) skipped")
                    continue
                }
                index[record.formID] = stat
            }
        }
        statIndex = index
        return index
    }

    /// FormID -> ModelBase over the MSTT/TREE/FURN/ACTI/CONT top groups
    /// (milestone 3.2 "widen base coverage"), built on first use and cached
    /// like statIndex. One top group per record type — unlike STAT there is
    /// no single shared group. Malformed records are skipped with a log,
    /// same mod-quirk handling as STAT.
    nonisolated private func modelBaseIndexBuildingIfNeeded() -> [UInt32: ModelBase] {
        if let modelBaseIndex {
            return modelBaseIndex
        }
        var index: [UInt32: ModelBase] = [:]
        for type in ModelBase.supportedTypes {
            guard let top = file.topGroup(of: type), let children = try? top.children() else {
                continue
            }
            for case let .record(record) in children where record.type == type {
                guard let base = try? ModelBase(record: record) else {
                    let id = FormID(record.formID).description
                    let name = type.description
                    Self.logger
                        .warning(
                            "malformed \(name, privacy: .public) \(id, privacy: .public) skipped"
                        )
                    continue
                }
                index[record.formID] = base
            }
        }
        modelBaseIndex = index
        return index
    }

    /// STAT first (largest, most common base type), falling back to the
    /// ModelBase index; nil when the base FormID resolves to neither.
    nonisolated private func resolveBase(
        formID: UInt32,
        statIndex: [UInt32: StaticObject],
        modelBaseIndex: [UInt32: ModelBase]
    ) -> ResolvedBase? {
        if let stat = statIndex[formID] {
            return ResolvedBase(formID: stat.formID, recordType: "STAT", modelPath: stat.modelPath)
        }
        if let base = modelBaseIndex[formID] {
            return ResolvedBase(
                formID: base.formID, recordType: base.recordType, modelPath: base.modelPath
            )
        }
        return nil
    }

    /// Flattens instances into the RenderScene (opaque first, alpha-test
    /// second — RenderScene orders that way), accumulates the world AABB from
    /// per-model bounds, and logs the one-line summary.
    nonisolated private func makeScene(
        found: FoundCell,
        grid: (x: Int32, y: Int32),
        instances: [ResolvedInstance],
        terrain: TerrainBuild?,
        counts: BuildCounts
    ) -> CellScene {
        // Per-instance world AABB (model bounds through the placement
        // transform) rides onto the draw items for frustum culling and
        // accumulates into the cell AABB for camera framing.
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
        // Terrain draws through its own splat pipeline list; ref DrawItem
        // ordering (instancing-ready grouping) stays intact.
        let renderScene = RenderScene(
            instances: placed,
            terrain: terrain?.items ?? []
        )
        if let world = terrain?.bounds {
            bounds = bounds.map { $0.union(world) } ?? world
        }
        let summary = CellLoadSummary(
            cellName: found.cell.editorID ?? "cell \(FormID(found.formID).description)",
            gridX: grid.x,
            gridY: grid.y,
            totalRefCount: counts.totalRefs,
            drawnRefCount: instances.count,
            unsupportedBaseSkipCount: counts.unsupportedBases,
            markerSkipCount: counts.markers,
            modelFailureSkipCount: counts.modelFailures,
            malformedRefSkipCount: counts.malformedRefs,
            modelCount: meshes.loadedCount,
            textureCount: textures.loadedCount,
            missingTextureCount: textures.missingCount,
            terrainQuadrantCount: terrain?.quadrantCount ?? 0,
            terrainLayerCount: terrain?.layerCount ?? 0,
            terrainLayerSkipCount: terrain?.layerSkipCount ?? 0
        )
        Self.logger.info("\(summary.summaryLine, privacy: .public)")
        return CellScene(
            renderScene: renderScene,
            summary: summary,
            bounds: bounds.map { (min: $0.min, max: $0.max) }
        )
    }
}
