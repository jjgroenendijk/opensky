// Drawable scene: engine Models -> GPU meshes + resolved textures -> grouped
// static + grass instances, terrain, water, sky, particles, and animations.
// Texture lookup stays caller-supplied so demo + VFS-backed scenes share it.

import Foundation
@preconcurrency import Metal
import OpenSkyFormatsCore
import OpenSkyShaderTypes
import simd

/// Resolves a material's texture key to a ready MTLTexture. `key` nil means
/// the material has no texture — implementations return a placeholder.
public typealias TextureProvider = (_ key: String?, _ usage: TextureUsage) -> MTLTexture

/// GPU-side material: resolved diffuse texture + the scalar parameters the
/// shader consumes. A blended static shape draws in the blended pass after water.
nonisolated public struct RenderMaterial: Sendable {
    public let diffuse: MTLTexture
    public let uvOffset: SIMD2<Float>
    public let uvScale: SIMD2<Float>
    public let alpha: Float
    /// nil -> opaque pipeline; set -> alpha-test pipeline variant.
    public let alphaTestThreshold: Float?
    /// Render both faces (cull mode none for this draw).
    public let doubleSided: Bool
    public let alphaBlend: Bool
    /// Set for an effect shape, which draws unlit.
    public let effect: RenderEffectMaterial?
    /// A water-shader shape: the water pass draws it, not a draw group.
    public let waterSurface: Bool

    public init(material: Material, textureProvider: TextureProvider) {
        diffuse = textureProvider(material.diffuseTexture, .color)
        uvOffset = material.uvOffset
        uvScale = material.uvScale
        alpha = material.alpha
        alphaTestThreshold = material.alphaTestThreshold
        doubleSided = material.doubleSided
        alphaBlend = material.alphaBlend
        effect = material.effect.map {
            RenderEffectMaterial(shading: $0, textureProvider: textureProvider)
        }
        waterSurface = material.waterSurface
    }
}

/// One uploaded engine Model: GPU meshes and materials, shared across instances. The mesh
/// library keys these by VFS path.
nonisolated public final class RenderModel: Sendable {
    public let meshes: [RenderMesh]
    public let materials: [RenderMaterial]

    public init(device: MTLDevice, model: Model, textureProvider: TextureProvider) throws {
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

    private init(meshes: [RenderMesh], renderMaterials: [RenderMaterial]) {
        self.meshes = meshes
        materials = renderMaterials
    }

    /// The model with its own skinning palettes, for one actor. The geometry and
    /// textures stay shared. A model with no skinned mesh is returned as is.
    public func posableCopy(device: MTLDevice) -> RenderModel {
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
}

/// One instanced draw call. Grouped by mesh and diffuse identity: a mesh belongs to one
/// model with one material per slot, so equal meshes mean equal material scalars.
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
        Self.drawsBlended(mesh: mesh, material: material, faceMorph: faceMorph)
    }

    /// Blend without an alpha test, on a rigid shape. Foliage and hair often
    /// set both, and keep the depth-writing alpha-test pass; only rigid shapes
    /// have a blended pipeline.
    static func drawsBlended(
        mesh: RenderMesh, material: RenderMaterial, faceMorph: FaceMorphBuffer?
    ) -> Bool {
        material.alphaBlend && material.alphaTestThreshold == nil && !mesh.isSkinned
            && faceMorph == nil
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

/// One terrain quadrant draw for the splat pipeline: quadrant mesh, its
/// per-vertex splat-weight stream (TerrainVertexLayout), the BTXT base
/// material, and the ATXT layer diffuses in blend order. Terrain always
/// draws opaque (docs/rendering/scene-drawing.md, terrain splat section).
nonisolated public struct TerrainDrawItem: Sendable {
    public let mesh: RenderMesh
    /// Two float4 weight lanes per vertex, vertex-count sized.
    public let weightsBuffer: MTLBuffer
    /// Base diffuse + UV params; alpha fields unused (terrain is opaque).
    public let material: RenderMaterial
    /// ATXT layer diffuses, <= TerrainConstant.maxLayers, blend order.
    public let layerTextures: [MTLTexture]
    /// TX01 normal maps of the base and of each layer, aligned with `layerTextures`.
    /// A flat placeholder stands in for a texture set without one.
    public let normals: TerrainNormalMaps
    public let modelMatrix: float4x4
    public let normalMatrix: float4x4
    /// World-space AABB for frustum culling; nil -> never culled.
    public let bounds: ModelBounds?

    public init(
        mesh: RenderMesh,
        weightsBuffer: MTLBuffer,
        material: RenderMaterial,
        layerTextures: [MTLTexture],
        normals: TerrainNormalMaps,
        modelMatrix: float4x4,
        normalMatrix: float4x4,
        bounds: ModelBounds?
    ) {
        self.mesh = mesh
        self.weightsBuffer = weightsBuffer
        self.material = material
        self.layerTextures = layerTextures
        self.normals = normals
        self.modelMatrix = modelMatrix
        self.normalMatrix = normalMatrix
        self.bounds = bounds
    }
}

/// The normal maps of one terrain quadrant draw.
nonisolated public struct TerrainNormalMaps: Sendable {
    public let base: MTLTexture
    public let layers: [MTLTexture]
    /// Base and layer maps that came from a TX01 path, for the panel readout.
    public let resolvedCount: Int

    public init(base: MTLTexture, layers: [MTLTexture], resolvedCount: Int) {
        self.base = base
        self.layers = layers
        self.resolvedCount = resolvedCount
    }
}

/// Exterior sky marker. Colors are procedural in the shader for now; this
/// value makes sky presence explicit per worldspace and mergeable per scene.
nonisolated public struct SkyParameters: Equatable, Sendable {
    public init() {}
}

/// One water surface: a cell plane at the CELL/WRLD water height, or a placed
/// mesh with a water shader. `look` comes from WATR.
nonisolated public struct WaterDrawItem: Sendable {
    public let mesh: RenderMesh
    public let modelMatrix: float4x4
    public let look: WaterLook
    public let bounds: ModelBounds?

    public init(mesh: RenderMesh, modelMatrix: float4x4, look: WaterLook, bounds: ModelBounds?) {
        self.mesh = mesh
        self.modelMatrix = modelMatrix
        self.look = look
        self.bounds = bounds
    }

    public init(
        mesh: RenderMesh,
        modelMatrix: float4x4,
        shallowColor: SIMD3<Float>,
        deepColor: SIMD3<Float>,
        reflectionColor: SIMD3<Float>,
        bounds: ModelBounds?
    ) {
        self.init(
            mesh: mesh, modelMatrix: modelMatrix,
            look: WaterLook(
                shallowColor: shallowColor, deepColor: deepColor, reflectionColor: reflectionColor
            ),
            bounds: bounds
        )
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
    /// clip's pose in the same `[String: float4x4]` shape, so unsimulated bones keep
    /// the animation.
    public var ragdollPoses: [UInt32: [String: float4x4]] = [:]

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
        placedWaterLook: WaterLook = .fallback
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
                let blended = DrawGroup.drawsBlended(
                    mesh: mesh, material: material, faceMorph: faceMorph
                )
                let modelMatrix = placement.transform * mesh.localTransform
                let instance = DrawInstance(
                    modelMatrix: modelMatrix,
                    normalMatrix: MatrixMath.normalMatrix(modelMatrix),
                    bounds: placement.bounds,
                    // A see-through surface casts no sun shadow.
                    castsShadows: placement.castsShadows && !blended,
                    receivesPointLights: placement.receivesPointLights,
                    receivesShadows: placement.receivesShadows,
                    referenceFormID: placement.referenceFormID,
                    layer: placement.layer,
                    owner: placement.owner
                )
                // Blended groups ride the alpha-tested list, so culling and
                // streaming need no third list; the scene pass draws them last.
                if material.alphaTestThreshold == nil, !blended {
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
    }

    /// Samples every resident actor at one shared world clock. A malformed
    /// runtime sample freezes only that actor; validated clips normally update.
    @discardableResult
    public func updateAnimations(at time: Float) -> Int {
        var poses: [ObjectIdentifier: SkeletonPose] = [:]
        var failedClips = Set<ObjectIdentifier>()
        var updatedMeshes = Set<ObjectIdentifier>()
        var updated = 0
        for animation in animations {
            guard let actor = animation as? any SharedPoseAnimation else {
                updated += animation.update(at: time)
                continue
            }
            let key = actor.sharedClipKey
            if failedClips.contains(key) {
                continue
            }
            let pose: SkeletonPose
            if let cached = poses[key] {
                pose = cached
            } else if let sampled = actor.sampleSharedPose(at: time) {
                poses[key] = sampled
                pose = sampled
            } else {
                failedClips.insert(key)
                continue
            }
            let posed = ragdollPoses[actor.actorFormID].map(pose.overriding) ?? pose
            updated += actor.apply(posed, updating: &updatedMeshes)
        }
        return updated
    }

    /// Restores all resident actor meshes to their NIF bind palettes.
    @discardableResult
    public func resetAnimationsToBindPose() -> Int {
        animations.reduce(0) { $0 + $1.resetToBindPose() }
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
    public var residencyAllocations: [MTLAllocation] {
        var seen = Set<ObjectIdentifier>()
        var allocations: [MTLAllocation] = []
        func add(_ resources: [MTLAllocation]) {
            allocations.append(contentsOf: resources.filter {
                seen.insert(ObjectIdentifier($0)).inserted
            })
        }
        for group in opaque + alphaTested {
            var resources: [MTLAllocation] = [
                group.mesh.vertexBuffer, group.mesh.indexBuffer, group.material.diffuse
            ]
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
            add([particle.instanceBuffer, particle.texture])
        }
        return allocations
    }
}
