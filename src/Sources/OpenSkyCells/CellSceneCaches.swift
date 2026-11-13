// The indexes and caches a cell scene builder fills on first use.

import Foundation
import Metal
import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyObjectAnimation
import OpenSkyPhysics
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyTerrain
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// The indexes and caches a cell scene builder fills on first use.
nonisolated public final class CellSceneCaches {
    /// Built on first use, like every index below.
    public var statIndex: [UInt32: StaticObject]?
    public var textureSetIndex: [UInt32: TextureSet]?
    var directionalMaterials = DirectionalMaterialCache()
    /// Door transitions, base objects, and cells read the load order through it.
    var loadOrderIndex: LoadOrderRecordIndex?
    /// MSTT/TREE/FURN/ACTI/CONT/DOOR; checked when a base is not a STAT.
    public var modelBaseIndex: [UInt32: ModelBase]?
    /// Keyed by WRLD FormID. Placement decides which exterior scene owns each ref.
    var exteriorPersistentRefs: [UInt32: [PlacedReference]] = [:]
    var exteriorPersistentPools: [UInt32: EnableParentPool] = [:]
    /// Each worldspace's `RNAM` references by cell, over every plugin.
    var largeReferenceIndex: [UInt32: [CellCoordinate: Set<UInt32>]] = [:]
    var largeReferenceSettings: LargeReferenceSettings?
    /// The cells that hold a temporary Is Full LOD reference, by WRLD FormID.
    var temporaryFullLODCellIndex: [UInt32: Set<CellCoordinate>] = [:]
    /// Keyed by WRLD FormID, with the same ownership rule as the persistent refs.
    var exteriorPersistentActors: [UInt32: [PlacedActor]] = [:]
    var encounterZones: EncounterZoneStore?
    /// Immutable decoded rig/idle assets; playback objects remain cell-owned.
    var actorAnimationClips: [ActorAnimationCacheKey: ActorAnimationClip] = [:]
    /// Lag bones by skeleton mesh path; nil inside records a skeleton without one.
    var actorLagBoneRigs: [String: ActorLagBoneRig?] = [:]
    /// Decoded expression TRI files by resource path. A file does not change while the
    /// game runs, so a rebuild reuses it; a failure is kept too.
    var faceMorphFiles: [String: Result<TRIFile, AssetLoadFailure>] = [:]
    /// Painted chargen face color maps as DDS bytes, by their synthetic texture key.
    var faceTintTextures: [String: Data] = [:]
    /// Object behaviour sets by project path; nil inside records a failed load.
    var objectBehaviorAssets: [String: BehaviorProjectAsset?] = [:]
    /// Sequence door rigs by mesh key; nil inside records a mesh without one.
    var sequenceDoorRigs: [String: SequenceDoorRig?] = [:]
    /// Graph object meshes' moving nodes by mesh key; nil inside records none.
    var movingPartRigs: [String: MovingPartRig?] = [:]
    /// Node controller rigs by mesh key; nil inside records a mesh without one.
    var nodeControllerRigs: [String: NodeControllerRig?] = [:]
    var worldspaceIndex: [UInt32: Worldspace]?
    /// Keyed by WRLD editor ID; holds only lookups made with `pluginLocalized`.
    var worldChildrenGroups: [String: FoundWorld] = [:]
    /// Keyed by WRLD load-order FormID, then by XCLC grid, over every plugin.
    var loadOrderExteriorCells: [UInt32: [SIMD2<Int32>: FoundCell]] = [:]
    /// LTEX FormID to its TXST texture keys; nil marks a broken chain.
    var terrainTextureKeyCache: [UInt32: TerrainTextureKeys?] = [:]
    /// Diffuse path to its mean gamma colour; nil marks a texture the CPU cannot decode.
    var terrainTextureMeans: [String: SIMD3<Float>?] = [:]
    /// Diffuse path and mip edge to the land texture the terrain LOD bake samples.
    var terrainLODTextures: [String: TerrainLODTexture?] = [:]
    /// LOD worldspace editor ID, lowercased, to its fitted terrain LOD curve.
    var terrainLODBrightnessByWorld: [String: TerrainLODBrightness] = [:]
    var waterTypeIndex: [UInt32: WaterType]?
    var waterPlaneMesh: RenderMesh?
    var landTextureIndex: [UInt32: LandTexture]?
    var grassIndex: [UInt32: Grass]?
    public var lightingTemplateIndex: [UInt32: LightingTemplate]?
    public var lightIndex: [UInt32: LightRecord]?
    /// `ADDN` `DATA` index to the add-on's model path, over the load order.
    var addOnModelIndex: [UInt32: String]?

    public init() {}
}
