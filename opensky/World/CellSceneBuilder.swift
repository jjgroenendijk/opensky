// Cell scene build (todo 2.7 scene build): walk one plugin's WRLD tree to an
// exterior cell, resolve each REFR's STAT base, load its NIF via MeshLibrary,
// and emit an instancing-ready RenderScene. Structural failures (worldspace
// or cell absent) throw; per-ref and per-asset failures log + skip + count
// and never abort the build (AGENTS.md mod-quirk rule).
//
// Group nesting: WRLD top group -> WRLD record + world-children group ->
// exterior block/sub-block groups -> CELL record + cell-children group ->
// persistent/temporary children groups -> REFR records. Reference: UESP
// "Skyrim Mod:Mod File Format" — Groups. Walk order + skip taxonomy:
// docs/engine/cell-scene.md.

import Foundation
import OSLog
import simd

nonisolated enum CellSceneError: Error, Equatable {
    /// No WRLD record carries the requested editor ID.
    case worldspaceNotFound(editorID: String)
    /// The worldspace holds no CELL at the requested grid slot.
    case cellNotFound(worldspaceEditorID: String, gridX: Int32, gridY: Int32)
}

/// Per-build skip accounting; folded into CellLoadSummary at the end.
private struct BuildCounts {
    var totalRefs = 0
    var malformedRefs = 0
    var nonSTATBases = 0
    var markers = 0
    var modelFailures = 0
}

/// One resolved placement, sortable into instancing-ready order.
private struct ResolvedInstance {
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
/// (nil children = cell without references).
private struct FoundCell {
    let cell: Cell
    let formID: UInt32
    let children: ESMGroup?
}

/// The world-children group plus the decoded WRLD it belongs to (DNAM default
/// land height feeds the LAND-less terrain fallback).
private struct FoundWorld {
    let children: ESMGroup
    let worldspace: Worldspace?
}

/// One built terrain patch ready to fold into the scene: its uploaded model,
/// world placement, model-space bounds, and drawn sub-mesh count.
private struct TerrainBuild {
    let model: RenderModel
    let transform: float4x4
    let bounds: ModelBounds?
    let quadrantCount: Int
}

/// Builds a CellScene from a plugin + asset libraries. Class (not struct)
/// because the STAT index is cached across builds. Single-threaded like the
/// libraries it drives: scene build runs once at startup.
nonisolated final class CellSceneBuilder {
    fileprivate static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "CellScene"
    )

    private let file: ESMFile
    private let meshes: MeshLibrary
    private let textures: TextureLibrary
    /// FormID -> STAT over the STAT top group, built on first use.
    private var statIndex: [UInt32: StaticObject]?

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
        return makeScene(
            found: found,
            grid: (x: gridX, y: gridY),
            instances: instances,
            terrain: terrain,
            counts: counts
        )
    }
}

extension CellSceneBuilder {
    /// The WRLD top group interleaves WRLD records with world-children groups
    /// labeled by the owning record's FormID. EDID match is exact (editor IDs
    /// are stable identifiers). A malformed WRLD is skipped — another
    /// worldspace may still match.
    private func worldChildrenGroup(editorID: String, localized: Bool) throws -> FoundWorld {
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
    private func findCell(
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
    private func cellChildrenGroup(
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
    private func collectReferences(
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

    /// Resolves refs to placed instances. Skip buckets: base not in the STAT
    /// index -> non-STAT; STAT without MODL -> marker; mesh load error ->
    /// model failure. Output is sorted by (normalized mesh path, FormID) so
    /// instances sharing a RenderModel are adjacent (instancing-ready) and
    /// the order is deterministic across runs.
    private func resolveInstances(
        refs: [PlacedReference],
        counts: inout BuildCounts
    ) -> [ResolvedInstance] {
        guard !refs.isEmpty else { return [] }
        let index = statIndexBuildingIfNeeded()
        var instances: [ResolvedInstance] = []
        for ref in refs {
            let id = ref.formID.description
            guard let stat = index[ref.base.rawValue] else {
                counts.nonSTATBases += 1
                let base = ref.base.description
                Self.logger.info(
                    """
                    REFR \(id, privacy: .public): base \(base, privacy: .public) \
                    not a STAT, skipped
                    """
                )
                continue
            }
            guard let modelPath = stat.modelPath else {
                counts.markers += 1
                let base = stat.formID.description
                Self.logger.info(
                    "REFR \(id, privacy: .public): marker STAT \(base, privacy: .public), skipped"
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
    /// skipped — refs pointing at them fall into the non-STAT bucket.
    private func statIndexBuildingIfNeeded() -> [UInt32: StaticObject] {
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

    /// Flattens instances into the RenderScene (opaque first, alpha-test
    /// second — RenderScene orders that way), accumulates the world AABB from
    /// per-model bounds, and logs the one-line summary.
    private func makeScene(
        found: FoundCell,
        grid: (x: Int32, y: Int32),
        instances: [ResolvedInstance],
        terrain: TerrainBuild?,
        counts: BuildCounts
    ) -> CellScene {
        // Terrain draws under the objects (opaque, no alpha test); appended
        // last so ref DrawItem ordering (instancing-ready grouping) is intact.
        var renderInstances = instances.map { ($0.model, $0.transform) }
        if let terrain {
            renderInstances.append((terrain.model, terrain.transform))
        }
        let renderScene = RenderScene(instances: renderInstances)
        var bounds: ModelBounds?
        for instance in instances {
            guard let local = meshes.bounds(forPath: instance.modelPath) else { continue }
            let world = local.transformed(by: instance.transform)
            bounds = bounds.map { $0.union(world) } ?? world
        }
        if let terrain, let local = terrain.bounds {
            let world = local.transformed(by: terrain.transform)
            bounds = bounds.map { $0.union(world) } ?? world
        }
        let summary = CellLoadSummary(
            cellName: found.cell.editorID ?? "cell \(FormID(found.formID).description)",
            gridX: grid.x,
            gridY: grid.y,
            totalRefCount: counts.totalRefs,
            drawnRefCount: instances.count,
            nonSTATSkipCount: counts.nonSTATBases,
            markerSkipCount: counts.markers,
            modelFailureSkipCount: counts.modelFailures,
            malformedRefSkipCount: counts.malformedRefs,
            modelCount: meshes.loadedCount,
            textureCount: textures.loadedCount,
            missingTextureCount: textures.missingCount,
            terrainQuadrantCount: terrain?.quadrantCount ?? 0
        )
        Self.logger.info("\(summary.summaryLine, privacy: .public)")
        return CellScene(
            renderScene: renderScene,
            summary: summary,
            bounds: bounds.map { (min: $0.min, max: $0.max) }
        )
    }
}

extension CellSceneBuilder {
    /// Builds terrain for the cell: from its LAND record when present, else a
    /// flat fallback plane at the worldspace DNAM default land height. Returns
    /// nil (no terrain drawn) when neither is available or the upload fails —
    /// terrain never aborts the cell build (mod-quirk rule). Placement puts the
    /// cell's south-west corner at (gridX*4096, gridY*4096), matching REFR world
    /// coordinates (docs/decisions/coordinates.md) so vertex local (col*128,
    /// row*128, height) lands at absolute world position.
    private func buildTerrain(found: FoundCell, worldspace: Worldspace?) -> TerrainBuild? {
        guard let grid = found.cell.grid else { return nil }
        let origin = SIMD3<Float>(Float(grid.x) * 4096, Float(grid.y) * 4096, 0)
        let transform = MatrixMath.translation(origin)

        let model: Model
        let quadrantCount: Int
        if let land = landRecord(in: found.children) {
            model = TerrainMeshBuilder.model(
                land: land,
                hiddenQuadrants: grid.quadFlags,
                materialForQuadrant: { terrainMaterial(for: $0, in: land) }
            )
            quadrantCount = model.meshes.count
        } else if let height = worldspace?.defaultLandHeight {
            // LAND-less exterior cell -> flat plane at the WRLD default land
            // height (Tamriel -27000). When DNAM is absent the correct engine
            // behavior is UNCONFIRMED (todo: probe); OpenSky draws no ground
            // rather than guess a floor height that could sit wrong.
            model = TerrainMeshBuilder.fallbackModel(defaultLandHeight: height)
            quadrantCount = model.meshes.count
        } else {
            return nil
        }
        guard !model.meshes.isEmpty else { return nil }

        let bounds = ModelBounds.containing(model: model)
        do {
            let render = try meshes.renderModel(for: model)
            return TerrainBuild(
                model: render, transform: transform, bounds: bounds,
                quadrantCount: quadrantCount
            )
        } catch {
            let reason = String(describing: error)
            Self.logger.warning("terrain upload failed (\(reason, privacy: .public)), skipped")
            return nil
        }
    }

    /// First LAND record in the cell's temporary-children group (type 9), where
    /// landscape lives (UESP Groups). Malformed decode -> nil (log + skip).
    private func landRecord(in cellChildren: ESMGroup?) -> Land? {
        guard let cellChildren, let children = try? cellChildren.children() else { return nil }
        for case let .group(group) in children where group.kind == .cellTemporaryChildren {
            guard let records = try? group.children() else { continue }
            for case let .record(record) in records where record.type == "LAND" {
                guard !record.isDeleted else { continue }
                if let land = try? Land(record: record) {
                    return land
                }
                let id = FormID(record.formID).description
                Self.logger.warning("malformed LAND \(id, privacy: .public) skipped")
            }
        }
        return nil
    }

    /// Resolves a quadrant's base texture BTXT -> LTEX (TNAM) -> TXST (TX00
    /// diffuse) into a Material. Any missing link -> Material.fallback (the
    /// TextureLibrary placeholders an unresolved diffuse path). Raw FormIDs
    /// suffice while scene build reads one plugin (same rule as STAT lookup).
    private func terrainMaterial(for quadrant: UInt8, in land: Land) -> Material {
        guard
            let base = land.baseTextures.first(where: { $0.quadrant == quadrant }),
            let ltexRecord = ESMWalk.record(withFormID: base.texture.rawValue, in: file),
            let ltex = try? LandTexture(record: ltexRecord),
            let textureSet = ltex.textureSet,
            let txstRecord = ESMWalk.record(withFormID: textureSet.rawValue, in: file),
            let txst = try? TextureSet(record: txstRecord),
            let diffuse = txst.diffusePath.flatMap({ NIFShaderTextureSet.vfsKey(for: $0) })
        else {
            return .fallback
        }
        // Normal maps are not sampled by the M2 material path yet (RenderMaterial
        // loads diffuse only); keep the key for when terrain lighting lands.
        let normal = txst.normalPath.flatMap { NIFShaderTextureSet.vfsKey(for: $0) }
        let fallback = Material.fallback
        return Material(
            diffuseTexture: diffuse,
            normalTexture: normal,
            uvOffset: fallback.uvOffset,
            uvScale: fallback.uvScale,
            alpha: fallback.alpha,
            glossiness: fallback.glossiness,
            specularColor: fallback.specularColor,
            specularStrength: fallback.specularStrength,
            doubleSided: false,
            alphaBlend: false,
            alphaTestThreshold: nil
        )
    }
}
