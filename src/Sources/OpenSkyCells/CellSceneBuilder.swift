// Walks one plugin's WRLD tree to a cell, resolves each REFR's base, and emits
// an instancing-ready RenderScene. A missing worldspace or cell throws; a bad
// record or asset is counted and skipped. Walk and skips: docs/engine/cell-scene.md.

import Foundation
import Metal
public import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
public import OpenSkyGameData
import OpenSkyObjectAnimation
public import OpenSkyPhysics
import OpenSkyRenderCore
public import OpenSkyRendering
public import OpenSkyRenderResources
public import OpenSkyTerrain
import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

/// A class because the record indexes are cached across builds.
/// Single-threaded, like the libraries it drives.
nonisolated public final class CellSceneBuilder {
    public let caches = CellSceneCaches()
    public static let logger = EngineLogger(
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
    var simulatesDynamicBodies = true
    /// Splits build time into asset phases for a benchmark; nil in normal play.
    public var loadPhases: LoadPhaseRecorder? {
        didSet {
            meshes.loadPhases = loadPhases
            textures.loadPhases = loadPhases
        }
    }

    public let distantLODBuilder: DistantLODBuilder?
    /// Every active plugin, lowest priority first; `file` alone when none are given.
    public let loadOrderPlugins: [(name: String, file: ESMFile)]
    /// Keeps each plugin's FormID index between sessions; nil walks every plugin.
    public var formIDIndexStore: (any FormIDIndexStore)?
    public var actorTemplateResolver: ActorTemplateResolver?
    public var actorVisualResolver: ActorVisualResolver?
    /// The session's roller; a cell build records its leveled placements here.
    public var leveling = LeveledListRoller()
    public let pluginName: String
    /// Built once, because `ESMFile.pluginHeader()` re-decodes on every call.
    public let formIDResolver: FormIDResolver
    /// TES4 0x80 selects table-ID lstrings instead of inline zstrings.
    public let pluginLocalized: Bool
    /// Resolves FULL/RNAM interaction text when the builder has a VFS.
    public let localizedStrings: LocalizedStrings?
    public var materialTypeIndex: MaterialTypeIndex?
    /// Records this builder could not decode, each FormID counted once.
    public internal(set) var skippedRecords = SkippedRecords()
    var skippedFormIDs: Set<UInt32> = []
    var skippedGroupOffsets: Set<Int> = []

    public init(
        file: ESMFile,
        meshes: MeshLibrary,
        textures: TextureLibrary,
        fileSystem: (any GameFileSource)? = nil,
        pluginName: String = "Skyrim.esm",
        plugins: [(name: String, file: ESMFile)] = [],
        localizationLanguage: String = LocalizationLanguageSettings.fallback,
        terrainLODConfigurationStore: TerrainLODConfigurationStore? = nil
    ) {
        self.file = file
        loadOrderPlugins = plugins.isEmpty ? [(pluginName, file)] : plugins
        self.meshes = meshes
        self.textures = textures
        self.fileSystem = fileSystem
        self.pluginName = pluginName
        pluginLocalized = file.isLocalized
        // Without a header, master index 0 falls through to the plugin itself.
        // The load-order space keeps the first plugin's own FormIDs unchanged.
        var skipped = SkippedRecords()
        formIDResolver = plugins.count > 1
            ? FormIDResolver.loadOrder(plugins.map(\.name))
            : FormIDResolver(pluginName: pluginName, masters: file.masters(noting: &skipped))
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
        assembler.resetTouchedAssets()
        let source = try modelIndex.exteriorBuildSource(
            worldspaceEditorID: worldspaceEditorID, gridX: gridX, gridY: gridY
        )
        let (world, found) = (source.world, source.cell)
        var counts = BuildCounts()
        let collected = referenceBuilder.collectTaggedReferences(in: found, counts: &counts)
        let coordinate = CellCoordinate(x: gridX, y: gridY)
        let refs = doorTransitions.exteriorReferences(
            local: collected.map(\.reference), world: world,
            coordinate: coordinate, localized: pluginLocalized
        )
        counts.totalRefs = refs.count + counts.malformedRefs
        let location = CellSceneLocation.exterior(coordinate)
        let parents = doorTransitions.persistentParentPool(in: world, localized: pluginLocalized)
        let resolved = referenceBuilder.states.effectiveReferences(
            (refs, collected), state: state, location: location,
            parentPool: parents, counts: &counts
        )
        let effective = resolved.references
        let collision = collisionBuilder.triggers
            .buildCollision(resolved: resolved, location: location)
        let instances = records.instances.resolveInstances(refs: effective, counts: &counts)
        let actors = actorBuilder.buildExteriorActors(
            cell: found, world: world, coordinate: coordinate, localized: pluginLocalized,
            deltas: resolved.deltas, collision: collision.staticCollision,
            parents: records.instances.enableParents(resolved, pool: parents)
        )
        let environment = assembler.buildEnvironment(found: found, worldspace: world.worldspace)
        let volumes = waterVolumeBuilder.waterVolumes(effective, found: found, in: environment)
        let scene = assembler.makeScene(
            cell: (found, (x: gridX, y: gridY)),
            instances: instances,
            geometry: CellGeometryBuild(
                location: location,
                doors: assembler.interactions.resolveDoors(refs: effective),
                interactions: assembler.interactions.resolveInteractions(refs: effective),
                terrain: environment.terrain,
                grass: environment.grass,
                water: environment.water,
                sky: environment.sky,
                lighting: nil,
                pointLights: [],
                staticCollision: collision.staticCollision,
                triggerVolumes: collision.triggerVolumes,
                dynamicBodies: collision.dynamicBodies,
                navmeshes: referenceBuilder.collectNavmeshes(in: found),
                actors: actors,
                world: world,
                referenceEntries: resolved.entries,
                stateSequence: state.sequence,
                vehicleFollowers: resolved.vehicleFollowers,
                waterVolumes: volumes
            ),
            counts: counts
        )
        let hazards = objectBuilder
            .hazards.collectHazards(in: found, resolved: resolved, parentPool: parents)
        return objectBuilder.hazards.finished(scene, hazards: hazards, collision: collision)
    }
}

nonisolated extension CellSceneBuilder.CellActorBuilder {
    var chargen: CellSceneBuilder.CellChargenBuilder {
        CellSceneBuilder.CellChargenBuilder(owner: owner)
    }
}

nonisolated extension CellSceneBuilder.CellActorBuilder {
    var morphs: CellSceneBuilder.CellMorphBuilder {
        CellSceneBuilder.CellMorphBuilder(owner: owner)
    }
}

nonisolated extension CellSceneBuilder.CellActorBuilder {
    var playerRig: CellSceneBuilder.CellPlayerRigBuilder {
        CellSceneBuilder.CellPlayerRigBuilder(owner: owner)
    }
}

nonisolated extension CellSceneBuilder.CellActorBuilder {
    var animation: CellSceneBuilder.CellActorAnimationBuilder {
        CellSceneBuilder.CellActorAnimationBuilder(owner: owner)
    }
}

nonisolated extension CellSceneBuilder.CellActorBuilder {
    var spawns: CellSceneBuilder.CellActorSpawnBuilder {
        CellSceneBuilder.CellActorSpawnBuilder(owner: owner)
    }
}

nonisolated extension CellSceneBuilder.CellActorBuilder {
    var resolver: CellSceneBuilder.CellActorResolver {
        CellSceneBuilder.CellActorResolver(owner: owner)
    }
}

nonisolated extension CellSceneBuilder.CellActorBuilder {
    var recorder: CellSceneBuilder.CellActorRecorder {
        CellSceneBuilder.CellActorRecorder(owner: owner)
    }
}

nonisolated extension CellSceneBuilder.CellSceneAssembler {
    var interactions: CellSceneBuilder.CellSceneInteractions {
        CellSceneBuilder.CellSceneInteractions(owner: owner)
    }
}

nonisolated extension CellSceneBuilder.CellSceneAssembler {
    var renderParts: CellSceneBuilder.CellSceneRenderParts {
        CellSceneBuilder.CellSceneRenderParts(owner: owner)
    }
}

nonisolated extension CellSceneBuilder.CellTerrainBuilder {
    public var grass: CellSceneBuilder.CellGrassBuilder {
        CellSceneBuilder.CellGrassBuilder(owner: owner)
    }
}

nonisolated extension CellSceneBuilder.CellTerrainBuilder {
    public var distantLOD: CellSceneBuilder.CellDistantLODBuilder {
        CellSceneBuilder.CellDistantLODBuilder(owner: owner)
    }
}

nonisolated extension CellSceneBuilder.CellTerrainBuilder {
    public var terrainLOD: CellSceneBuilder.CellTerrainLODBuilder {
        CellSceneBuilder.CellTerrainLODBuilder(owner: owner)
    }
}

nonisolated extension CellSceneBuilder.CellTerrainBuilder {
    public var textures: CellSceneBuilder.CellTerrainTextures {
        CellSceneBuilder.CellTerrainTextures(owner: owner)
    }
}

nonisolated extension CellSceneBuilder.CellObjectBuilder {
    var hazards: CellSceneBuilder.CellHazardBuilder {
        CellSceneBuilder.CellHazardBuilder(owner: owner)
    }
}

nonisolated extension CellSceneBuilder.CellObjectBuilder {
    var animated: CellSceneBuilder.CellAnimatedObjectBuilder {
        CellSceneBuilder.CellAnimatedObjectBuilder(owner: owner)
    }
}

nonisolated extension CellSceneBuilder.CellReferenceBuilder {
    var largeReferences: CellSceneBuilder.CellLargeReferenceBuilder {
        CellSceneBuilder.CellLargeReferenceBuilder(owner: owner)
    }
}

nonisolated extension CellSceneBuilder.CellReferenceBuilder {
    var states: CellSceneBuilder.CellReferenceStateBuilder {
        CellSceneBuilder.CellReferenceStateBuilder(owner: owner)
    }

    var placedRecords: PlacedRecordLookup {
        states.placedRecords
    }
}

nonisolated extension CellSceneBuilder {
    public var collisionBuilder: CellSceneBuilder.CellCollisionBuilder {
        CellSceneBuilder.CellCollisionBuilder(owner: self)
    }
}

nonisolated extension CellSceneBuilder.CellCollisionBuilder {
    public var triggers: CellSceneBuilder.CellTriggerBuilder {
        CellSceneBuilder.CellTriggerBuilder(owner: owner)
    }
}

nonisolated extension CellSceneBuilder.CellCollisionBuilder {
    public var doorCollision: CellSceneBuilder.CellDoorCollisionBuilder {
        CellSceneBuilder.CellDoorCollisionBuilder(owner: owner)
    }
}

nonisolated extension CellSceneBuilder.CellCollisionBuilder {
    public var router: CellSceneBuilder.CellCollisionRouter {
        CellSceneBuilder.CellCollisionRouter(owner: owner)
    }
}

nonisolated extension CellSceneBuilder {
    var records: CellSceneBuilder.CellRecordWalker {
        CellSceneBuilder.CellRecordWalker(owner: self)
    }

    var preparation: CellSceneBuilder.CellIndexPreparation {
        CellSceneBuilder.CellIndexPreparation(owner: self)
    }

    public func prepareIndexes(worldspace: String?) {
        preparation.prepareIndexes(worldspace: worldspace)
    }

    /// The walk from the plugin's groups to a cell and its placed references.
    nonisolated struct CellRecordWalker {
        let owner: CellSceneBuilder
    }

    /// The indexes a build reads, made once before the first cell.
    nonisolated struct CellIndexPreparation {
        let owner: CellSceneBuilder
    }

    nonisolated struct CellActorBuilder {
        let owner: CellSceneBuilder
    }

    /// The static and dynamic collision, trigger volumes, and door collision of a cell.
    nonisolated public struct CellCollisionBuilder {
        let owner: CellSceneBuilder
    }

    /// Routes each collision shape into its partition or dynamic body.
    nonisolated public struct CellCollisionRouter {
        let owner: CellSceneBuilder
    }

    /// The door collision and moving collision sources of a cell.
    nonisolated public struct CellDoorCollisionBuilder {
        let owner: CellSceneBuilder
    }

    /// The trigger volumes of a cell.
    nonisolated public struct CellTriggerBuilder {
        let owner: CellSceneBuilder
    }

    /// Records each assembled actor into the cell build.
    nonisolated struct CellActorRecorder {
        let owner: CellSceneBuilder
    }

    /// Resolves each placed actor to its visual, state, and equipment.
    nonisolated struct CellActorResolver {
        let owner: CellSceneBuilder
    }

    /// Spawned and levelled actors, and the floors they stand on.
    nonisolated struct CellActorSpawnBuilder {
        let owner: CellSceneBuilder
    }

    /// The animation clips and lag-bone rigs of actors.
    nonisolated struct CellActorAnimationBuilder {
        let owner: CellSceneBuilder
    }

    /// The player's body and first-person rig.
    nonisolated struct CellPlayerRigBuilder {
        let owner: CellSceneBuilder
    }

    /// The head and face morphs of an actor.
    nonisolated struct CellMorphBuilder {
        let owner: CellSceneBuilder
    }

    /// The character generation tints of an actor's face.
    nonisolated struct CellChargenBuilder {
        let owner: CellSceneBuilder
    }

    nonisolated struct CellRecordIndex {
        let owner: CellSceneBuilder
    }

    /// The model, texture-set, and material indexes and the exterior build source.
    nonisolated struct CellModelIndex {
        let owner: CellSceneBuilder
    }

    nonisolated struct CellReferenceBuilder {
        let owner: CellSceneBuilder
    }

    /// The runtime state and relocation of placed references.
    nonisolated struct CellReferenceStateBuilder {
        let owner: CellSceneBuilder
    }

    /// The large references and full LOD placements of a worldspace.
    nonisolated struct CellLargeReferenceBuilder {
        let owner: CellSceneBuilder
    }

    nonisolated public struct CellInteriorBuilder {
        let owner: CellSceneBuilder
    }

    /// The lighting of an interior cell: its template, fog, and lights.
    nonisolated public struct CellInteriorLighting {
        let owner: CellSceneBuilder
    }

    /// The door transitions and a worldspace's exterior doors and persistent references.
    nonisolated public struct CellDoorTransitionBuilder {
        let owner: CellSceneBuilder
    }

    nonisolated public struct CellPreviewBuilder {
        let owner: CellSceneBuilder
    }

    /// Where a preview stands, and the cell that holds a previewed reference.
    nonisolated public struct CellPreviewPlaces {
        let owner: CellSceneBuilder
    }

    nonisolated struct CellObjectBuilder {
        let owner: CellSceneBuilder
    }

    /// Animated objects, sequence doors, and node controllers.
    nonisolated struct CellAnimatedObjectBuilder {
        let owner: CellSceneBuilder
    }

    /// The hazards and vehicles of a cell.
    nonisolated struct CellHazardBuilder {
        let owner: CellSceneBuilder
    }

    nonisolated public struct CellTerrainBuilder {
        let owner: CellSceneBuilder
    }

    /// The texture layers and render items of a terrain cell.
    nonisolated public struct CellTerrainTextures {
        let owner: CellSceneBuilder
    }

    /// The generated terrain LOD textures and their brightness.
    nonisolated public struct CellTerrainLODBuilder {
        let owner: CellSceneBuilder
    }

    /// The distant LOD scene and its water.
    nonisolated public struct CellDistantLODBuilder {
        let owner: CellSceneBuilder
    }

    /// The grass of a terrain cell.
    nonisolated public struct CellGrassBuilder {
        let owner: CellSceneBuilder
    }

    nonisolated struct CellSceneAssembler {
        let owner: CellSceneBuilder
    }

    /// The render placements, particles, bounds, and summary of a scene.
    nonisolated struct CellSceneRenderParts {
        let owner: CellSceneBuilder
    }

    /// The doors and interactions a scene offers the player.
    nonisolated struct CellSceneInteractions {
        let owner: CellSceneBuilder
    }

    nonisolated struct CellWaterBuilder {
        let owner: CellSceneBuilder
    }

    /// The water volumes of a cell: their collision planes and currents.
    nonisolated struct CellWaterVolumeBuilder {
        let owner: CellSceneBuilder
    }

    /// The model and behaviour each placed reference draws with, sorted for instancing.
    nonisolated struct CellInstanceResolver {
        let owner: CellSceneBuilder
    }
}

nonisolated extension CellSceneBuilder.CellRecordWalker {
    var instances: CellSceneBuilder.CellInstanceResolver {
        CellSceneBuilder.CellInstanceResolver(owner: owner)
    }
}
