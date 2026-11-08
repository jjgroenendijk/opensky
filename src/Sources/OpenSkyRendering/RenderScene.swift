// Drawable scene: engine Models -> GPU meshes + resolved textures -> grouped
// static + grass instances, terrain, water, sky, particles, and animations.
// Texture lookup stays caller-supplied so demo + VFS-backed scenes share it.

import Foundation
@preconcurrency @unsafe public import Metal
public import OpenSkyFormatsCore
public import OpenSkyRenderCore
public import OpenSkyRenderResources
import OpenSkyShaderTypes
public import simd

/// One uploaded engine Model: GPU meshes and materials, shared across instances. The mesh
/// library keys these by VFS path.
nonisolated public final class RenderModel: Sendable {
    public let meshes: [RenderMesh]
    public let materials: [RenderMaterial]

    public init(device: any MTLDevice, model: Model, textureProvider: TextureProvider) throws {
        meshes = try model.meshes.map { try RenderMesh(device: device, mesh: $0) }
        materials = model.materials.map {
            RenderMaterial(material: $0, textureProvider: textureProvider)
        }
    }

    init(meshes: [RenderMesh], materials: [Material], textureProvider: TextureProvider) {
        self.meshes = meshes
        self.materials = materials.map {
            RenderMaterial(material: $0, textureProvider: textureProvider)
        }
    }

    init(meshes: [RenderMesh], renderMaterials: [RenderMaterial]) {
        self.meshes = meshes
        materials = renderMaterials
    }

    /// The model with its own skinning palettes, for one actor. The geometry and
    /// textures stay shared. A model with no skinned mesh is returned as is.
    public func posableCopy(device: any MTLDevice) -> RenderModel {
        guard meshes.contains(where: \.isSkinned) else { return self }
        return RenderModel(
            meshes: meshes.map { $0.posableCopy(device: device) }, renderMaterials: materials
        )
    }
}

/// One placed model going into a RenderScene: instance transform plus the
/// world-space AABB used for frustum culling (model bounds pushed through
/// the transform). nil bounds -> the instance is never culled.
nonisolated public struct RenderPlacement: Sendable {
    public let model: RenderModel
    public let transform: float4x4
    public let bounds: ModelBounds?
    /// Distant LOD stays outside sun-shadow caster set. Default true keeps
    /// regular cell geometry + actors unchanged.
    public let castsShadows: Bool
    /// Distant geometry uses world lighting only. Skipping local lights keeps
    /// large billboard batches out of the per-fragment point-light loop.
    public let receivesPointLights: Bool
    public let receivesShadows: Bool
    /// The REFR this placement draws, only when a simulated rigid body moves it
    /// every frame; zero otherwise. See `DrawInstance.referenceFormID`.
    public let referenceFormID: UInt32
    /// Per-mesh actor-local FaceGen expression buffers. Empty for every
    /// placement except a face model with an associated expression TRI.
    public let faceMorphs: [ObjectIdentifier: FaceMorphBuffer]
    /// Which scene role this placement plays, for layer isolation. It lives here, not
    /// on the shared `RenderMesh`, because one mesh can play different roles.
    /// `.statics` is the default.
    public let layer: RenderLayer
    /// The actor reference this placement draws, or zero. A membrane overlay finds its
    /// target's meshes by it.
    public let owner: UInt32
    /// The reference's emittance (`XEMI`), for shapes with external emittance.
    public var emittance: EmittanceSource?
    /// A TREE's wind motion.
    public var treeMotion: TreeMotion?

    public init(
        model: RenderModel,
        transform: float4x4,
        bounds: ModelBounds? = nil,
        castsShadows: Bool = true,
        receivesPointLights: Bool = true,
        receivesShadows: Bool = true,
        referenceFormID: UInt32 = 0,
        faceMorphs: [ObjectIdentifier: FaceMorphBuffer] = [:],
        layer: RenderLayer = .statics,
        owner: UInt32 = 0
    ) {
        self.model = model
        self.transform = transform
        self.bounds = bounds
        self.castsShadows = castsShadows
        self.receivesPointLights = receivesPointLights
        self.receivesShadows = receivesShadows
        self.referenceFormID = referenceFormID
        self.faceMorphs = faceMorphs
        self.layer = layer
        self.owner = owner
    }
}

/// One instance within a DrawGroup: world-space matrices + culling AABB.
nonisolated public struct DrawInstance: Sendable {
    public let modelMatrix: float4x4
    /// Inverse-transpose of modelMatrix (world-space normals).
    public let normalMatrix: float4x4
    /// World-space AABB for frustum culling. Model-level bounds pushed
    /// through the instance transform — shared by every mesh of the
    /// instance, so conservative per mesh. nil -> never culled.
    public let bounds: ModelBounds?
    public let castsShadows: Bool
    public let receivesPointLights: Bool
    public let receivesShadows: Bool
    /// The REFR a simulated rigid body moves, or zero. The upload passes substitute
    /// the live pose for the baked one (`Renderer.drawn(_:)`), which is cheaper than
    /// rebuilding draw groups every frame.
    public var referenceFormID: UInt32 = 0
    /// The placement's scene role, so the layer filter and the `layerCategory` debug
    /// channel agree.
    public var layer: RenderLayer = .statics
    /// See `RenderPlacement.owner`.
    public var owner: UInt32 = 0
    /// The interior room this static instance sits in, or `RoomPortalGraph.noRoom`.
    public var room = RoomPortalGraph.noRoom
    /// See `RenderPlacement.emittance`.
    public var emittance: EmittanceSource?
    /// See `RenderPlacement.treeMotion`.
    public var treeMotion: TreeMotion?

    /// The `InstanceTransform.instanceColor` of a static, with this frame's region colours.
    public func instanceColor(regions: [UInt32: SIMD3<Float>]) -> SIMD4<Float> {
        EmittanceSource.colour(of: emittance, regions: regions)
    }
}

/// One instanced draw call. Grouped by mesh, diffuse, and draw state: a mesh belongs to
/// one model with one material per slot, so equal meshes mean equal material scalars.
nonisolated public struct DrawGroup: Sendable {
    public let mesh: RenderMesh
    public let material: RenderMaterial
    public let faceMorph: FaceMorphBuffer?
    /// Mutable only during scene construction (GroupAccumulator).
    public private(set) var instances: [DrawInstance]
    /// Kept with `instances`, so the lighting center costs no per-frame pass.
    private var originSum: SIMD3<Float>

    init(
        mesh: RenderMesh,
        material: RenderMaterial,
        faceMorph: FaceMorphBuffer?,
        instances: [DrawInstance]
    ) {
        self.mesh = mesh
        self.material = material
        self.faceMorph = faceMorph
        self.instances = []
        originSum = .zero
        self.instances.reserveCapacity(instances.count)
        for instance in instances {
            append(instance)
        }
    }

    fileprivate mutating func append(_ instance: DrawInstance) {
        instances.append(instance)
        let origin = instance.modelMatrix.columns.3
        originSum += SIMD3(origin.x, origin.y, origin.z)
    }

    /// Adds in the same order as one `append` each, so the lighting center is bit-equal.
    fileprivate mutating func append(contentsOf added: [DrawInstance]) {
        instances.reserveCapacity(instances.count + added.count)
        for instance in added {
            append(instance)
        }
    }

    /// Mean instance origin at the baked pose: the point the nearest lights are
    /// picked for.
    public var lightingCenter: SIMD3<Float> {
        originSum / Float(max(1, instances.count))
    }

    public var castsShadows: Bool {
        instances.first?.castsShadows == true
    }

    public var receivesShadows: Bool {
        instances.first?.receivesShadows == true
    }

    /// The group's scene role. Every instance shares it: the layer is part of
    /// the grouping key, so a group never mixes roles.
    public var layer: RenderLayer {
        instances.first?.layer ?? .statics
    }

    public var drawsBlended: Bool {
        Self.drawsBlended(material)
    }

    /// Blood on a weapon, drawn only while the weapon is bloody.
    public var isWeaponBlood: Bool {
        material.effect?.weaponBlood ?? false
    }

    /// Blend without an alpha test, such as a beard or a waterfall. Foliage and
    /// hair often set both, and keep the depth-writing alpha-test pass. An additive
    /// blend always draws blended, because it only adds light.
    static func drawsBlended(_ material: RenderMaterial) -> Bool {
        material.additiveBlend != nil
            || material.alphaBlend && material.alphaTestThreshold == nil
            && !material.drawState.screenDoor
    }

    /// A refraction shape reads the scene drawn before it, so it draws in its own pass.
    public var drawsRefraction: Bool {
        Self.drawsRefraction(material)
    }

    static func drawsRefraction(_ material: RenderMaterial) -> Bool {
        material.surface.flags & UInt32(ShadingTerm.refraction.rawValue) != 0
    }
}

/// Ordered mesh+material grouping: first appearance fixes group order so
/// composed scenes stay deterministic across recompositions.
nonisolated private struct GroupAccumulator {
    private struct Key: Hashable {
        let mesh: ObjectIdentifier
        let diffuse: ObjectIdentifier
        let castsShadows: Bool
        let receivesPointLights: Bool
        let receivesShadows: Bool
        let faceMorph: ObjectIdentifier?
        let layer: RenderLayer
        let alphaBlend: Bool
        let isEffect: Bool
    }

    private var indexByKey: [Key: Int] = [:]
    private(set) var groups: [DrawGroup] = []

    mutating func add(
        mesh: RenderMesh,
        material: RenderMaterial,
        faceMorph: FaceMorphBuffer?,
        instance: DrawInstance
    ) {
        let key = Key(
            mesh: ObjectIdentifier(mesh),
            diffuse: ObjectIdentifier(material.diffuse),
            castsShadows: instance.castsShadows,
            receivesPointLights: instance.receivesPointLights,
            receivesShadows: instance.receivesShadows,
            faceMorph: faceMorph.map(ObjectIdentifier.init),
            layer: instance.layer,
            alphaBlend: material.alphaBlend,
            isEffect: material.effect != nil
        )
        if let index = indexByKey[key] {
            groups[index].append(instance)
        } else {
            indexByKey[key] = groups.count
            groups.append(DrawGroup(
                mesh: mesh, material: material, faceMorph: faceMorph, instances: [instance]
            ))
        }
    }

    /// A group built by an accumulator shares one key, so it is looked up once. A
    /// group that mixes flags falls back to one lookup per instance.
    mutating func add(group: DrawGroup) {
        guard
            let first = group.instances.first,
            group.instances.allSatisfy({ Self.sharesKey($0, first) })
        else {
            for instance in group.instances {
                add(
                    mesh: group.mesh,
                    material: group.material,
                    faceMorph: group.faceMorph,
                    instance: instance
                )
            }
            return
        }
        let key = Key(
            mesh: ObjectIdentifier(group.mesh),
            diffuse: ObjectIdentifier(group.material.diffuse),
            castsShadows: first.castsShadows,
            receivesPointLights: first.receivesPointLights,
            receivesShadows: first.receivesShadows,
            faceMorph: group.faceMorph.map(ObjectIdentifier.init),
            layer: first.layer,
            alphaBlend: group.material.alphaBlend,
            isEffect: group.material.effect != nil
        )
        if let index = indexByKey[key] {
            groups[index].append(contentsOf: group.instances)
        } else {
            indexByKey[key] = groups.count
            groups.append(group)
        }
    }

    private static func sharesKey(_ lhs: DrawInstance, _ rhs: DrawInstance) -> Bool {
        lhs.castsShadows == rhs.castsShadows && lhs.receivesPointLights == rhs.receivesPointLights
            && lhs.receivesShadows == rhs.receivesShadows && lhs.layer == rhs.layer
    }
}

/// Draw lists for one frame. Placements become instances grouped by mesh and material,
/// opaque before alpha-tested. Terrain draws once per patch through the splat pipeline.
nonisolated public struct RenderScene: Sendable {
    public let opaque: [DrawGroup]
    public let alphaTested: [DrawGroup]
    public let terrain: [TerrainDrawItem]
    public let water: [WaterDrawItem]
    public let sky: SkyParameters?
    public let lighting: RenderLighting?
    public let pointLights: [RenderPointLight]
    /// Cell-owned GRAS meshes grouped across placements/cells for one
    /// instanced draw per mesh/material after runtime visibility filtering.
    public let grass: [GrassDrawGroup]
    /// Cell-owned CPU particle systems + their texture/instance buffers.
    public let particles: [ParticlePlayback]
    /// Cell-owned actor playback objects; references disappear on cell eviction.
    public let animations: [any RenderAnimation]
    /// Simulated bone poses, keyed by the ACHR each ragdoll stands for. Laid over the
    /// clip's pose; an unsimulated bone moves with its nearest simulated ancestor.
    public var ragdollPoses: [UInt32: [String: float4x4]] = [:]
    /// The pose of each falling or resting cut head, keyed by the actor it came from.
    public var severedHeadPoses: [UInt32: [String: float4x4]] = [:]
    /// The interior's rooms and portals; nil turns room culling off.
    public let rooms: RoomPortalGraph?
    /// The placement each moving reference was built with, so a live pose becomes a
    /// draw delta against what this scene holds.
    public let referencePlacements: [UInt32: float4x4]
    /// The distant LOD's fitted curve; nil draws with the vanilla one.
    public var terrainLODBrightness: TerrainLODBrightness?

    /// One mesh of a placement as a draw. A see-through surface casts no sun shadow.
    private static func instance(
        of placement: RenderPlacement, mesh: RenderMesh, state: MaterialDrawState, seeThrough: Bool
    ) -> DrawInstance {
        let modelMatrix = placement.transform * mesh.localTransform
        var instance = DrawInstance(
            modelMatrix: modelMatrix,
            normalMatrix: MatrixMath.normalMatrix(modelMatrix),
            bounds: placement.bounds,
            castsShadows: placement.castsShadows && !seeThrough && state.castsShadows,
            receivesPointLights: placement.receivesPointLights && !state.distantLOD,
            receivesShadows: placement.receivesShadows && state.receivesShadows,
            referenceFormID: placement.referenceFormID,
            layer: placement.layer,
            owner: placement.owner
        )
        instance.emittance = placement.emittance
        instance.treeMotion = placement.treeMotion
        return instance
    }

    public init(
        instances: [RenderPlacement],
        animations: [any RenderAnimation] = [],
        terrain: [TerrainDrawItem] = [],
        water: [WaterDrawItem] = [],
        sky: SkyParameters? = nil,
        lighting: RenderLighting? = nil,
        pointLights: [RenderPointLight] = [],
        grass: [GrassRenderPlacement] = [],
        particles: [ParticlePlayback] = [],
        placedWaterLook: WaterLook = .fallback,
        rooms: RoomPortalGraph? = nil
    ) {
        var opaque = GroupAccumulator()
        var alphaTested = GroupAccumulator()
        var water = water
        for placement in instances {
            let model = placement.model
            for mesh in model.meshes {
                // Slot validated against the producing Model by RenderModel
                // construction order; guard anyway — external data upstream.
                guard mesh.materialSlot < model.materials.count else { continue }
                let material = model.materials[mesh.materialSlot]
                if material.waterSurface {
                    water.append(WaterDrawItem(
                        mesh: mesh, modelMatrix: placement.transform * mesh.localTransform,
                        look: placedWaterLook, bounds: placement.bounds
                    ))
                    continue
                }
                let faceMorph = placement.faceMorphs[ObjectIdentifier(mesh)]
                let seeThrough = DrawGroup.drawsBlended(material)
                    || DrawGroup.drawsRefraction(material)
                var instance = Self.instance(
                    of: placement, mesh: mesh, state: material.drawState, seeThrough: seeThrough
                )
                instance.room = Self.room(of: placement, in: rooms)
                // Blended groups ride the alpha-tested list, so culling and
                // streaming need no third list; the scene pass draws them last.
                if material.alphaTestThreshold == nil, !seeThrough {
                    opaque.add(
                        mesh: mesh, material: material, faceMorph: faceMorph, instance: instance
                    )
                } else {
                    alphaTested.add(
                        mesh: mesh, material: material, faceMorph: faceMorph, instance: instance
                    )
                }
            }
        }
        self.opaque = opaque.groups
        self.alphaTested = alphaTested.groups
        self.terrain = terrain
        self.water = water
        self.sky = sky
        self.lighting = lighting
        self.pointLights = pointLights
        var grassGroups = GrassGroupAccumulator()
        for placement in grass {
            grassGroups.add(placement)
        }
        self.grass = grassGroups.groups
        self.particles = particles
        self.animations = animations
        self.rooms = rooms
        referencePlacements = Self.referencePlacements(of: instances)
    }

    private static func referencePlacements(of instances: [RenderPlacement]) -> [UInt32: float4x4] {
        var placements: [UInt32: float4x4] = [:]
        for placement in instances where placement.referenceFormID != 0 {
            placements[placement.referenceFormID] = placement.transform
        }
        return placements
    }

    /// Only still statics get a room: an actor or a simulated body moves out of it.
    private static func room(of placement: RenderPlacement, in rooms: RoomPortalGraph?) -> UInt32 {
        guard
            let rooms, let bounds = placement.bounds,
            placement.layer == .statics, placement.referenceFormID == 0
        else { return RoomPortalGraph.noRoom }
        return rooms.soleRoom(touching: bounds)
    }

    /// Merges already-built scenes into one draw-list union — grid/streaming
    /// composition (CellSceneComposition). Each source scene already carries
    /// absolute world-space matrices from its own cell build, so merging
    /// needs no re-transform. Groups with the same mesh + material fold
    /// together (adjacent cells placing the same model share one instanced
    /// draw); `residencyAllocations` still dedups across the merged lists.
    public init(merging scenes: [RenderScene]) {
        var opaque = GroupAccumulator()
        var alphaTested = GroupAccumulator()
        var grass = GrassGroupAccumulator()
        for scene in scenes {
            for group in scene.opaque {
                opaque.add(group: group)
            }
            for group in scene.alphaTested {
                alphaTested.add(group: group)
            }
            for group in scene.grass {
                grass.add(group)
            }
        }
        self.opaque = opaque.groups
        self.alphaTested = alphaTested.groups
        terrain = scenes.flatMap(\.terrain)
        water = scenes.flatMap(\.water)
        sky = scenes.lazy.compactMap(\.sky).first
        lighting = scenes.lazy.compactMap(\.lighting).first
        pointLights = scenes.flatMap(\.pointLights)
        self.grass = grass.groups
        particles = scenes.flatMap(\.particles)
        animations = scenes.flatMap(\.animations)
        // Room indices belong to one graph, so two graphs turn room culling off.
        let graphs = scenes.compactMap(\.rooms)
        rooms = graphs.count == 1 ? graphs.first : nil
        terrainLODBrightness = scenes.lazy.compactMap(\.terrainLODBrightness).first
        referencePlacements = scenes.reduce(into: [:]) { merged, scene in
            merged.merge(scene.referencePlacements) { kept, _ in kept }
        }
    }

    /// CPU light culling: stable distance order, original scene order as
    /// tie-break. The renderer reads `nearestPointLightPick` instead.
    public func nearestPointLights(to position: SIMD3<Float>, limit: Int) -> [RenderPointLight] {
        let pick = nearestPointLightPick(to: position, limit: limit)
        return (0 ..< pick.count).map { pointLights[Int(pick.indices[$0])] }
    }

    /// Per-draw uniform ring slots one frame can need: one per group +
    /// terrain item.
    public var drawCount: Int {
        opaque.count + alphaTested.count + terrain.count + water.count + grass.count
            + particles.count
    }

    /// Static instances across all groups — sizes the renderer's
    /// per-instance transform ring.
    public var instanceCount: Int {
        opaque.reduce(0) { $0 + $1.instances.count }
            + alphaTested.reduce(0) { $0 + $1.instances.count }
            + grass.reduce(0) { $0 + $1.instances.count }
    }

    /// Every GPU allocation the scene touches, deduplicated, for the residency set.
    public var residencyAllocations: [any MTLAllocation] {
        var seen = Set<ObjectIdentifier>()
        var allocations: [any MTLAllocation] = []
        func add(_ resources: [any MTLAllocation]) {
            allocations.append(contentsOf: resources.filter {
                seen.insert(ObjectIdentifier($0)).inserted
            })
        }
        for group in opaque + alphaTested {
            var resources: [any MTLAllocation] = [group.mesh.vertexBuffer, group.mesh.indexBuffer]
                + group.material.textures
            if let skinning = group.mesh.skinningBuffer {
                resources.append(skinning)
            }
            if let matrices = group.mesh.boneMatrixBuffer {
                resources.append(matrices)
            }
            if let morph = group.faceMorph {
                resources.append(morph.buffer)
            }
            add(resources)
        }
        for item in terrain {
            add([
                item.mesh.vertexBuffer, item.mesh.indexBuffer,
                item.weightsBuffer, item.material.diffuse
            ])
            add(item.layerTextures)
            add([item.normals.base] + item.normals.layers)
        }
        for item in water {
            add([item.mesh.vertexBuffer, item.mesh.indexBuffer])
        }
        for group in grass {
            add([
                group.mesh.vertexBuffer, group.mesh.indexBuffer,
                group.material.diffuse
            ])
        }
        for particle in particles {
            add(particle.residencyAllocations)
        }
        return allocations
    }
}
