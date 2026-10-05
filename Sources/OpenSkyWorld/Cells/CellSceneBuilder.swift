// Walks one plugin's WRLD tree to a cell, resolves each REFR's base, and emits
// an instancing-ready RenderScene. A missing worldspace or cell throws; a bad
// record or asset is counted and skipped. Walk and skips: docs/engine/cell-scene.md.

import Foundation
import Metal
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorldState
import OSLog
import simd

nonisolated public enum CellSceneError: Error, Equatable {
    /// No WRLD record carries the requested editor ID.
    case worldspaceNotFound(editorID: String)
    /// The worldspace holds no CELL at the requested grid slot.
    case cellNotFound(worldspaceEditorID: String, gridX: Int32, gridY: Int32)
    case interiorCellNotFound(formID: FormID)
    case doorReferenceNotFound(formID: FormID)
    case doorHasNoTeleport(formID: FormID)
    case teleportDestinationNotFound(formID: FormID)
    /// A record the build needs exists but its typed decode threw.
    case malformedRecord(type: FourCC, formID: FormID, reason: String)
}

/// Per-build skip accounting; folded into CellLoadSummary at the end.
nonisolated public struct BuildCounts: Sendable {
    public var totalRefs = 0
    public var malformedRefs = 0
    public var unsupportedBases = 0
    public var markers = 0
    public var modelFailures = 0
    /// Dropped like an initially-disabled record.
    public var runtimeDisabled = 0
    /// Not the header `deleted` flag, which never reaches a build.
    public var runtimeDeleted = 0
    /// Dropped by the initially-disabled flag or a disabled enable parent.
    public var baselineDisabled = 0
    /// `XESP` links whose parent is outside this build's references.
    public var unresolvedEnableParents = 0
    /// Kept apart from `totalRefs`, the plugin's own count.
    public var spawnedRefs = 0
    /// Spawns past the 24-bit object ID space. Zero in practice.
    public var unaddressableSpawns = 0
}

/// A STAT or ModelBase base resolved to its drawable model path.
nonisolated public struct ResolvedBase: Sendable {
    public let formID: FormID
    public let recordType: FourCC
    /// Nil = marker base (no MODL), nothing to draw.
    public let modelPath: String?
    /// The base is flagged as a marker, so its model is not drawn either.
    public let isEditorMarker: Bool
}

/// One resolved placement, sortable into instancing-ready order.
nonisolated public struct ResolvedInstance {
    /// Normalized mesh path — primary grouping key.
    public let sortKey: String
    /// REFR FormID — deterministic tie-break within one model.
    public let formID: UInt32
    /// Raw MODL path, for the bounds lookup in MeshLibrary.
    public let modelPath: String
    public let model: RenderModel
    public let transform: float4x4
}

/// A located CELL and its cell-children group; nil children means no references.
nonisolated public struct FoundCell: Sendable {
    public let cell: Cell
    public let formID: UInt32
    public let children: ESMGroup?
}

/// The world-children group and its WRLD; DNAM feeds the LAND-less terrain fallback.
nonisolated public struct FoundWorld: Sendable {
    public let children: ESMGroup
    public let worldspace: Worldspace?
}

/// A class because the record indexes are cached across builds.
/// Single-threaded, like the libraries it drives.
nonisolated public final class CellSceneBuilder {
    public static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "CellScene"
    )

    public let file: ESMFile
    public let meshes: MeshLibrary
    public let textures: TextureLibrary
    public let fileSystem: (any GameFileSource)?
    public let collisionModels: NIFCollisionLibrary?
    public var collisionPartitionCache = CellCollisionPartitionCache()
    /// Whether movable clutter joins the dynamic world. Off only for builds that
    /// want the immutable collision set, such as `openskycli collision`.
    public var simulatesDynamicBodies = true
    /// Splits build time into asset phases for a benchmark; nil in normal play.
    public var loadPhases: LoadPhaseRecorder? {
        didSet {
            meshes.loadPhases = loadPhases
            textures.loadPhases = loadPhases
        }
    }

    public let distantLODBuilder: DistantLODBuilder?
    /// Built on first use, like every index below.
    public var statIndex: [UInt32: StaticObject]?
    /// MSTT/TREE/FURN/ACTI/CONT/DOOR; checked when a base is not a STAT.
    public var modelBaseIndex: [UInt32: ModelBase]?
    /// Keyed by WRLD FormID. Placement decides which exterior scene owns each ref.
    public var exteriorPersistentRefs: [UInt32: [PlacedReference]] = [:]
    var exteriorPersistentPools: [UInt32: [FormID: PlacedReference]] = [:]
    /// Keyed by WRLD FormID, with the same ownership rule as the persistent refs.
    public var exteriorPersistentActors: [UInt32: [PlacedActor]] = [:]
    public var actorTemplateResolver: ActorTemplateResolver?
    public var actorVisualResolver: ActorVisualResolver?
    /// Immutable decoded rig/idle assets; playback objects remain cell-owned.
    public var actorAnimationClips: [ActorAnimationCacheKey: ActorAnimationClip] = [:]
    /// Decoded expression TRI files by resource path. A file does not change while the
    /// game runs, so a rebuild reuses it; a failure is kept too.
    var faceMorphFiles: [String: Result<TRIFile, AssetLoadFailure>] = [:]
    public let pluginName: String
    /// Built once, because `ESMFile.pluginHeader()` re-decodes on every call.
    public let formIDResolver: FormIDResolver
    /// TES4 0x80 selects table-ID lstrings instead of inline zstrings.
    public let pluginLocalized: Bool
    /// Resolves FULL/RNAM interaction text when the builder has a VFS.
    public let localizedStrings: LocalizedStrings?
    public var worldspaceIndex: [UInt32: Worldspace]?
    /// Keyed by WRLD editor ID; holds only lookups made with `pluginLocalized`.
    var worldChildrenGroups: [String: FoundWorld] = [:]
    /// Keyed by the world-children group's file offset, then by XCLC grid.
    var exteriorCellIndexes: [Int: [SIMD2<Int32>: FoundCell]] = [:]
    /// LTEX FormID to its TXST diffuse key; nil marks a broken chain.
    var terrainDiffuseKeys: [UInt32: String?] = [:]
    public var waterTypeIndex: [UInt32: WaterType]?
    public var waterPlaneMesh: RenderMesh?
    public var landTextureIndex: [UInt32: LandTexture]?
    public var grassIndex: [UInt32: Grass]?
    public var lightingTemplateIndex: [UInt32: LightingTemplate]?
    public var lightIndex: [UInt32: LightRecord]?
    public var materialTypeIndex: MaterialTypeIndex?
    /// Records this builder could not decode, each FormID counted once.
    public private(set) var skippedRecords = SkippedRecords()
    private var skippedFormIDs: Set<UInt32> = []
    private var skippedGroupOffsets: Set<Int> = []

    public init(
        file: ESMFile,
        meshes: MeshLibrary,
        textures: TextureLibrary,
        fileSystem: (any GameFileSource)? = nil,
        pluginName: String = "Skyrim.esm",
        localizationLanguage: String = LocalizationLanguageSettings.fallback,
        terrainLODConfigurationStore: TerrainLODConfigurationStore? = nil
    ) {
        self.file = file
        self.meshes = meshes
        self.textures = textures
        self.fileSystem = fileSystem
        self.pluginName = pluginName
        pluginLocalized = file.isLocalized
        // Without a header, master index 0 falls through to the plugin itself.
        var skipped = SkippedRecords()
        formIDResolver = FormIDResolver(pluginName: pluginName, masters: skipped.masters(of: file))
        skippedRecords = skipped
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

    /// - Parameter state: runtime changes laid over the plugin; `.empty` builds
    ///   what the plugin authored.
    public func buildScene(
        worldspaceEditorID: String,
        gridX: Int32,
        gridY: Int32,
        state: WorldStateSnapshot = .empty
    ) throws -> CellScene {
        // The touched keys drive unload eviction (docs/engine/cell-streaming.md).
        resetTouchedAssets()
        let source = try exteriorBuildSource(
            worldspaceEditorID: worldspaceEditorID, gridX: gridX, gridY: gridY
        )
        let world = source.world
        let found = source.cell
        var counts = BuildCounts()
        let collected = collectTaggedReferences(in: found.children, counts: &counts)
        let coordinate = CellCoordinate(x: gridX, y: gridY)
        let refs = exteriorReferences(
            local: collected.map(\.reference), world: world.children,
            coordinate: coordinate, localized: pluginLocalized
        )
        counts.totalRefs = refs.count + counts.malformedRefs
        let location = CellSceneLocation.exterior(coordinate)
        let parents = persistentParentPool(in: world.children, localized: pluginLocalized)
        let resolved = effectiveReferences(
            refs: refs, collected: collected, state: state, location: location,
            parentPool: parents, counts: &counts
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
        scene.hazards = collectHazards(in: found.children, resolved: resolved, parentPool: parents)
        scene.assets = drainTouchedAssets()
        return scene
    }
}

nonisolated extension CellSceneBuilder {
    /// Decodes `record`, or counts it in `skippedRecords` and returns nil.
    /// Cell searches re-read records on every build, so a FormID counts once.
    nonisolated public func decodeOrSkip<Value>(
        _ record: ESMRecord,
        using decode: (ESMRecord) throws -> Value
    ) -> Value? {
        do {
            return try decode(record)
        } catch {
            guard skippedFormIDs.insert(record.formID).inserted else { return nil }
            skippedRecords.note(record.type, error: error)
            let id = FormID(record.formID).description
            let type = record.type.description
            let reason = String(describing: error)
            Self.logger.warning(
                """
                malformed \(type, privacy: .public) \(id, privacy: .public) skipped: \
                \(reason, privacy: .public)
                """
            )
            return nil
        }
    }

    /// The group's children, or nil with the error counted once under its record type.
    nonisolated public func childrenOrSkip(_ group: ESMGroup) -> [ESMGroup.Child]? {
        do {
            return try group.children()
        } catch {
            guard skippedGroupOffsets.insert(group.contentRange.lowerBound).inserted else {
                return nil
            }
            skippedRecords.note(group.recordType ?? "GRUP", error: error)
            Self.logMalformedGroup(error)
            return nil
        }
    }

    /// For static walks, which hold no builder to count the skip in.
    nonisolated public static func loggedChildren(_ group: ESMGroup) -> [ESMGroup.Child]? {
        do {
            return try group.children()
        } catch {
            logMalformedGroup(error)
            return nil
        }
    }

    private static func logMalformedGroup(_ error: any Error) {
        let reason = String(describing: error)
        logger.warning("malformed group skipped: \(reason, privacy: .public)")
    }

    /// Returns the first WRLD group whose EDID matches exactly. A malformed WRLD
    /// is skipped, because another one may still match.
    nonisolated public func worldChildrenGroup(
        editorID: String,
        localized: Bool
    ) throws -> FoundWorld {
        guard localized == pluginLocalized else {
            return try uncachedWorldChildrenGroup(editorID: editorID, localized: localized)
        }
        if let cached = worldChildrenGroups[editorID] {
            return cached
        }
        let found = try uncachedWorldChildrenGroup(editorID: editorID, localized: localized)
        worldChildrenGroups[editorID] = found
        return found
    }

    /// Decodes every WRLD up to the match, so `worldChildrenGroup` keeps the result.
    nonisolated private func uncachedWorldChildrenGroup(
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
                guard
                    let world = decodeOrSkip(record, using: {
                        try Worldspace(record: $0, localized: localized)
                    })
                else { continue }
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

    /// Matches the decoded XCLC grid, never the unreliable block labels. The first
    /// decodable CELL in depth-first order wins. Skips the persistent CELL, which
    /// also carries XCLC (0,0) (`persistentCell(in:)`).
    nonisolated public func findCell(
        in group: ESMGroup,
        gridX: Int32,
        gridY: Int32,
        localized: Bool
    ) -> FoundCell? {
        let grid = SIMD2(gridX, gridY)
        guard localized == pluginLocalized else {
            return exteriorCellIndex(of: group, localized: localized)[grid]
        }
        let key = group.contentRange.lowerBound
        if let cached = exteriorCellIndexes[key] {
            return cached[grid]
        }
        let index = exteriorCellIndex(of: group, localized: localized)
        exteriorCellIndexes[key] = index
        return index[grid]
    }

    /// Every exterior CELL under `group` by grid. One full walk costs about as much
    /// as a few single-cell searches, and each later build then skips the walk.
    nonisolated private func exteriorCellIndex(
        of group: ESMGroup,
        localized: Bool
    ) -> [SIMD2<Int32>: FoundCell] {
        var index: [SIMD2<Int32>: FoundCell] = [:]
        indexExteriorCells(in: group, localized: localized, into: &index)
        return index
    }

    nonisolated private func indexExteriorCells(
        in group: ESMGroup,
        localized: Bool,
        into index: inout [SIMD2<Int32>: FoundCell]
    ) {
        // Prune a malformed subtree: other cells may live in a sibling block.
        guard let children = childrenOrSkip(group) else { return }
        for (position, child) in children.enumerated() {
            switch child {
            case let .record(record) where record.type == "CELL" && group.kind != .worldChildren:
                guard
                    let cell = decodeOrSkip(record, using: {
                        try Cell(record: $0, localized: localized)
                    }),
                    let grid = cell.grid, index[SIMD2(grid.x, grid.y)] == nil
                else { continue }
                index[SIMD2(grid.x, grid.y)] = FoundCell(
                    cell: cell,
                    formID: record.formID,
                    children: cellChildrenGroup(
                        following: position, in: children, cellFormID: record.formID
                    )
                )
            case let .group(sub)
                where sub.kind == .exteriorCellBlock || sub.kind == .exteriorCellSubBlock:
                indexExteriorCells(in: sub, localized: localized, into: &index)
            default:
                break
            }
        }
    }

    /// The worldspace persistent CELL: the one CELL stored directly in the world
    /// children group, not in a block (xEdit names it "<Persistent Worldspace Cell>").
    nonisolated public func persistentCell(
        in worldChildren: ESMGroup,
        localized: Bool
    ) -> FoundCell? {
        guard let children = childrenOrSkip(worldChildren) else { return nil }
        for (index, child) in children.enumerated() {
            guard
                case let .record(record) = child, record.type == "CELL",
                let cell = decodeOrSkip(record, using: {
                    try Cell(record: $0, localized: localized)
                })
            else { continue }
            return FoundCell(
                cell: cell,
                formID: record.formID,
                children: cellChildrenGroup(
                    following: index, in: children, cellFormID: record.formID
                )
            )
        }
        return nil
    }

    /// The group follows its CELL among the same siblings, labeled with its FormID.
    nonisolated public func cellChildrenGroup(
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

    /// Skips unknown bases, markers, and failed meshes. Sorted by
    /// (mesh path, FormID) so shared models sit together for instancing.
    nonisolated public func resolveInstances(
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
            guard let modelPath = resolved.modelPath, !resolved.isEditorMarker else {
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
            if let instance = loadInstance(ref: ref, modelPath: modelPath, counts: &counts) {
                instances.append(instance)
            }
        }
        return instances.sorted { ($0.sortKey, $0.formID) < ($1.sortKey, $1.formID) }
    }

    /// Nil when the mesh fails to load or holds only editor-marker geometry.
    nonisolated private func loadInstance(
        ref: PlacedReference,
        modelPath: String,
        counts: inout BuildCounts
    ) -> ResolvedInstance? {
        do {
            return try ResolvedInstance(
                sortKey: (try? VirtualFileSystem.normalize(modelPath)) ?? modelPath,
                formID: ref.formID.rawValue,
                modelPath: modelPath,
                model: meshes.model(path: modelPath),
                transform: MatrixMath.placement(
                    position: ref.placement.position,
                    rotation: ref.placement.rotation,
                    scale: ref.scale
                )
            )
        } catch MeshLibraryError.editorMarkerOnly {
            counts.markers += 1
        } catch {
            counts.modelFailures += 1
            let id = ref.formID.description
            let reason = String(describing: error)
            Self.logger.warning(
                """
                REFR \(id, privacy: .public): model \(modelPath, privacy: .public) \
                failed (\(reason, privacy: .public)), skipped
                """
            )
        }
        return nil
    }
}
