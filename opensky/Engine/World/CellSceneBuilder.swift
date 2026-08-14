// Cell scene build (todo 2.7 scene build, widened to MSTT/TREE/FURN/ACTI/CONT/DOOR
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
    case interiorCellNotFound(formID: FormID)
    case doorReferenceNotFound(formID: FormID)
    case doorHasNoTeleport(formID: FormID)
    case teleportDestinationNotFound(formID: FormID)
}

/// Per-build skip accounting; folded into CellLoadSummary at the end.
nonisolated struct BuildCounts {
    var totalRefs = 0
    var malformedRefs = 0
    var unsupportedBases = 0
    var markers = 0
    var modelFailures = 0
    /// References the runtime disabled since load (issue #160): dropped from
    /// this build exactly as an initially-disabled record is.
    var runtimeDisabled = 0
    /// References the runtime deleted since load. Distinct from the record
    /// header's `deleted` flag, which never reaches a build at all.
    var runtimeDeleted = 0
    /// Objects the running game placed in this cell (issue #177): dropped
    /// items today. Counted apart from `totalRefs`, which is the plugin's own
    /// reference count and must stay comparable across builds.
    var spawnedRefs = 0
    /// Spawned objects dropped because their generated sequence has outrun the
    /// 24-bit object ID a FormID can hold. Always zero in practice; counted so
    /// that it is visible rather than silent if it ever is not.
    var unaddressableSpawns = 0
}

/// One base record resolved to its drawable model path, regardless of
/// whether it came from the STAT or ModelBase (MSTT/TREE/FURN/ACTI/CONT/DOOR)
/// index — resolveInstances treats both the same past this point.
nonisolated struct ResolvedBase {
    let formID: FormID
    let recordType: FourCC
    /// Nil = marker base (no MODL), nothing to draw.
    let modelPath: String?
}

/// One resolved placement, sortable into instancing-ready order.
nonisolated struct ResolvedInstance {
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
nonisolated struct FoundWorld {
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
    let fileSystem: VirtualFileSystem?
    let collisionModels: NIFCollisionLibrary?
    var collisionPartitionCache = CellCollisionPartitionCache()
    /// Whether movable clutter leaves the immutable collision set and joins the
    /// dynamic world (issues #193 and #392).
    ///
    /// On by default since #392: the real-data probe now has every one of a
    /// vanilla farmhouse's fifty-one simulated references coming to rest where
    /// it was authored, inside a step cost the frame can afford. It stayed off
    /// through #193 because neither held — half that clutter left the geometry
    /// it started in and fell out of the world — and a barrel that sometimes
    /// sinks through a shelf is a worse world than one that never moves. It
    /// remains a setting rather than a constant so a build that only wants the
    /// immutable collision set, such as `openskycli collision`, can say so.
    var simulatesDynamicBodies = true
    let distantLODBuilder: DistantLODBuilder?
    /// FormID -> STAT over the STAT top group, built on first use.
    var statIndex: [UInt32: StaticObject]?
    /// FormID -> ModelBase over MSTT/TREE/FURN/ACTI/CONT/DOOR top groups,
    /// built on first use. Checked when a ref's base is not a STAT.
    var modelBaseIndex: [UInt32: ModelBase]?
    /// XTEL refs stored in each WRLD persistent CELL, keyed by WRLD FormID.
    /// Physical placement decides which streamed exterior scene owns them.
    var exteriorPersistentTeleportRefs: [UInt32: [PlacedReference]] = [:]
    /// ACHRs stored in each WRLD persistent CELL, keyed by WRLD FormID —
    /// same ownership rule as the teleport refs above (5.5 actor streaming).
    var exteriorPersistentActors: [UInt32: [PlacedActor]] = [:]
    /// Template + visual actor resolvers, built on the first actor-bearing
    /// cell and cached like statIndex. Build-queue confined.
    var actorTemplateResolver: ActorTemplateResolver?
    var actorVisualResolver: ActorVisualResolver?
    /// Immutable decoded rig/idle assets; playback objects remain cell-owned.
    var actorAnimationClips: [ActorAnimationCacheKey: ActorAnimationClip] = [:]
    /// Plugin file name feeding FaceGen path resolution (FormIDResolver).
    let pluginName: String
    /// Master-list resolver for this plugin, built once here because
    /// `ESMFile.pluginHeader()` re-decodes the header on every call and every
    /// indexed reference needs a resolution.
    let formIDResolver: FormIDResolver
    /// TES4 0x80 selects table-ID lstrings instead of inline zstrings.
    let pluginLocalized: Bool
    /// Resolves FULL/RNAM interaction text when the builder has a VFS.
    let localizedStrings: LocalizedStrings?
    /// Water/environment indexes + reusable plane mesh. Build-queue confined
    /// like the existing record indexes and asset libraries.
    var worldspaceIndex: [UInt32: Worldspace]?
    var waterTypeIndex: [UInt32: WaterType]?
    var waterPlaneMesh: RenderMesh?
    var landTextureIndex: [UInt32: LandTexture]?
    var grassIndex: [UInt32: Grass]?
    var lightingTemplateIndex: [UInt32: LightingTemplate]?
    var lightIndex: [UInt32: LightRecord]?
    /// MATT materials plus the Havok-hash and LTEX lookups into them
    /// (issue #358), built on first use like the indexes above. Collision and
    /// terrain both resolve their surface material through it at build time.
    var materialTypeIndex: MaterialTypeIndex?

    init(
        file: ESMFile,
        meshes: MeshLibrary,
        textures: TextureLibrary,
        fileSystem: VirtualFileSystem? = nil,
        pluginName: String = "Skyrim.esm",
        localizationLanguage: String = LocalizationLanguageSettings.fallback,
        terrainLODConfigurationStore: TerrainLODConfigurationStore? = nil
    ) {
        self.file = file
        self.meshes = meshes
        self.textures = textures
        self.fileSystem = fileSystem
        self.pluginName = pluginName
        let header = try? file.pluginHeader()
        pluginLocalized = header?.isLocalized ?? false
        // A plugin whose header failed to decode still resolves its own
        // records: master index 0 then falls through to the plugin itself.
        formIDResolver = header?.formIDResolver(pluginName: pluginName)
            ?? FormIDResolver(pluginName: pluginName, masters: [])
        localizedStrings = fileSystem.map {
            LocalizedStrings(vfs: $0, pluginName: pluginName, language: localizationLanguage)
        }
        collisionModels = fileSystem.map(NIFCollisionLibrary.init(fileSystem:))
        distantLODBuilder = fileSystem.map {
            DistantLODBuilder(
                fileSystem: $0,
                meshes: meshes,
                textures: textures,
                configurationStore: terrainLODConfigurationStore ?? .fallback()
            )
        }
    }

    /// - Parameter state: runtime deviations to lay over the plugin's data
    ///   (issue #160). `.empty` builds exactly what the plugin authored, which
    ///   is what a build with no session state behind it wants.
    func buildScene(
        worldspaceEditorID: String,
        gridX: Int32,
        gridY: Int32,
        state: WorldStateSnapshot = .empty
    ) throws -> CellScene {
        // Clear any stale working set so this build's touched keys are exactly
        // this cell's mesh + texture set (recorded onto the CellScene for
        // unload eviction — docs/engine/cell-streaming.md).
        resetTouchedAssets()
        let source = try exteriorBuildSource(
            worldspaceEditorID: worldspaceEditorID,
            gridX: gridX,
            gridY: gridY
        )
        let world = source.world
        let found = source.cell
        var counts = BuildCounts()
        let collected = collectTaggedReferences(in: found.children, counts: &counts)
        let coordinate = CellCoordinate(x: gridX, y: gridY)
        let refs = exteriorReferences(
            local: collected.map(\.reference),
            world: world.children,
            coordinate: coordinate,
            localized: pluginLocalized
        )
        counts.totalRefs = refs.count + counts.malformedRefs
        let location = CellSceneLocation.exterior(coordinate)
        let resolved = effectiveReferences(
            refs: refs, collected: collected, state: state, location: location, counts: &counts
        )
        let effective = resolved.references
        let collision = buildCollision(resolved: resolved, location: location)
        let instances = resolveInstances(refs: effective, counts: &counts)
        let actors = buildExteriorActors(
            cellChildren: found.children,
            world: world.children,
            coordinate: coordinate,
            localized: pluginLocalized,
            deltas: resolved.deltas
        )
        let environment = buildEnvironment(found: found, worldspace: world.worldspace)
        var scene = makeScene(
            found: found,
            grid: (x: gridX, y: gridY),
            instances: instances,
            geometry: CellGeometryBuild(
                location: location,
                doors: resolveDoors(refs: effective),
                interactions: resolveInteractions(refs: effective),
                terrain: environment.terrain,
                grass: environment.grass,
                water: environment.water,
                sky: environment.sky,
                lighting: nil,
                pointLights: [],
                staticCollision: collision.staticCollision,
                triggerVolumes: collision.triggerVolumes,
                dynamicBodies: collision.dynamicBodies,
                navmeshes: Self.collectNavmeshes(in: found.children),
                actors: actors,
                worldspaceMusicType: world.worldspace?.musicType,
                referenceEntries: resolved.entries,
                stateSequence: state.sequence
            ),
            counts: counts
        )
        scene.assets = drainTouchedAssets()
        return scene
    }
}

nonisolated extension CellSceneBuilder {
    /// The WRLD top group interleaves WRLD records with world-children groups
    /// labeled by the owning record's FormID. EDID match is exact (editor IDs
    /// are stable identifiers). A malformed WRLD is skipped — another
    /// worldspace may still match.
    nonisolated func worldChildrenGroup(
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
    nonisolated func findCell(
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
    nonisolated func cellChildrenGroup(
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

    /// Resolves refs to placed instances. Skip buckets: base FormID resolves
    /// to neither the STAT nor the ModelBase (MSTT/TREE/FURN/ACTI/CONT/DOOR)
    /// index -> unsupported base; a resolved base without MODL -> marker;
    /// mesh load error -> model failure. Output is sorted by (normalized
    /// mesh path, FormID) so instances sharing a RenderModel are adjacent
    /// (instancing-ready) and the order is deterministic across runs.
    nonisolated func resolveInstances(
        refs: [PlacedReference],
        counts: inout BuildCounts
    ) -> [ResolvedInstance] {
        guard !refs.isEmpty else { return [] }
        let statIndex = statIndexBuildingIfNeeded()
        let modelBaseIndex = modelBaseIndexBuildingIfNeeded()
        let lightIndex = lightIndexBuildingIfNeeded()
        var instances: [ResolvedInstance] = []
        for ref in refs where lightIndex[ref.base.rawValue] == nil {
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
}
