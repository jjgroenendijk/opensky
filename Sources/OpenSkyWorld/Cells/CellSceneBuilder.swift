// Walks one plugin's WRLD tree to a cell, resolves each REFR's base, and emits
// an instancing-ready RenderScene. A missing worldspace or cell throws; a bad
// record or asset is counted and skipped. Walk and skips: docs/engine/cell-scene.md.

import Foundation
import Metal
import OpenSkyFormatsCore
import OpenSkyFormatsESM
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
    public let distantLODBuilder: DistantLODBuilder?
    /// Built on first use, like every index below.
    public var statIndex: [UInt32: StaticObject]?
    /// MSTT/TREE/FURN/ACTI/CONT/DOOR; checked when a base is not a STAT.
    public var modelBaseIndex: [UInt32: ModelBase]?
    /// Keyed by WRLD FormID. Placement decides which exterior scene owns each ref.
    public var exteriorPersistentTeleportRefs: [UInt32: [PlacedReference]] = [:]
    /// Keyed by WRLD FormID, with the same ownership rule as the teleport refs.
    public var exteriorPersistentActors: [UInt32: [PlacedActor]] = [:]
    public var actorTemplateResolver: ActorTemplateResolver?
    public var actorVisualResolver: ActorVisualResolver?
    /// Immutable decoded rig/idle assets; playback objects remain cell-owned.
    public var actorAnimationClips: [ActorAnimationCacheKey: ActorAnimationClip] = [:]
    public let pluginName: String
    /// Built once, because `ESMFile.pluginHeader()` re-decodes on every call.
    public let formIDResolver: FormIDResolver
    /// TES4 0x80 selects table-ID lstrings instead of inline zstrings.
    public let pluginLocalized: Bool
    /// Resolves FULL/RNAM interaction text when the builder has a VFS.
    public let localizedStrings: LocalizedStrings?
    public var worldspaceIndex: [UInt32: Worldspace]?
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

    /// Depth-first; matches the decoded XCLC grid, never the unreliable block labels.
    nonisolated public func findCell(
        in group: ESMGroup,
        gridX: Int32,
        gridY: Int32,
        localized: Bool
    ) -> FoundCell? {
        // Prune a malformed subtree: the target may live in a sibling block.
        guard let children = childrenOrSkip(group) else { return nil }
        for (index, child) in children.enumerated() {
            switch child {
            case let .record(record) where record.type == "CELL":
                guard
                    let cell = decodeOrSkip(record, using: {
                        try Cell(record: $0, localized: localized)
                    }),
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

    /// Skips unknown bases, markers without MODL, and failed meshes. Sorted by
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
