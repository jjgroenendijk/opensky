// Ray-traced sun shadows on GPUs with hardware ray tracing: the frame builds the
// acceleration structures when the scene changes, and the static-mesh and terrain
// pipelines trace one ray to the sun per pixel. See docs/rendering/ray-traced-shadows.md.

import Metal
import MetalKit
import OpenSkyShaderTypes

/// The pipelines that trace: static meshes and terrain.
struct RayTracedPipelines {
    let opaque: MTLRenderPipelineState
    let alphaTest: MTLRenderPipelineState
    let terrain: MTLRenderPipelineState
}

public struct RayTracedShadowState {
    public let availability: RayTracingAvailability
    /// The player's choice; it applies only where the GPU is available.
    public var enabled = false
    /// Draws the traced shadow alone, white where lit.
    public var showOnly = false
    /// Nil on a GPU without hardware ray tracing.
    let shaded: RayTracedPipelines?
    let shadowView: RayTracedPipelines?
    var scene: RayTracedShadowScene?
    var isCurrent = false

    init(
        availability: RayTracingAvailability,
        pipelines: (RayTracedPipelines, RayTracedPipelines)?
    ) {
        self.availability = availability
        shaded = pipelines?.0
        shadowView = pipelines?.1
    }

    public var isActive: Bool {
        enabled && shaded != nil
    }

    public var stats: RayTracedShadowStats {
        scene?.stats ?? RayTracedShadowStats()
    }
}

extension Renderer {
    static func makeRayTracing(
        library: MTLLibrary, compiler: PipelineCache, view: MTKView
    ) -> RayTracedShadowState {
        let availability = RayTracingAvailability.of(view.device)
        guard availability.isAvailable else {
            return RayTracedShadowState(availability: availability, pipelines: nil)
        }
        func make(_ constants: [FunctionConstantIndex]) throws -> RayTracedPipelines {
            func mesh(alphaTest: Bool) throws -> MTLRenderPipelineState {
                var variant = MeshPipelineVariant(alphaTest: alphaTest)
                variant.enabling = constants
                return try makeMeshPipeline(
                    variant,
                    library: library,
                    compiler: compiler,
                    view: view
                )
            }
            return try RayTracedPipelines(
                opaque: mesh(alphaTest: false), alphaTest: mesh(alphaTest: true),
                terrain: makeTerrainPipeline(
                    library: library, compiler: compiler, view: view, enabling: constants
                )
            )
        }
        // A pipeline that fails to build leaves the effect unavailable, not the renderer.
        let pipelines = try? (make([.rayTracedShadows]), make([.rayTracedShadows, .rayShadowView]))
        return RayTracedShadowState(
            availability: pipelines == nil
                ? .unavailable(reason: "The ray-traced pipelines failed to build") : availability,
            pipelines: pipelines
        )
    }

    /// The pipelines this frame draws static meshes and terrain with, or nil for the
    /// shadow-map ones.
    var rayTracedPipelines: RayTracedPipelines? {
        guard rayTracedShadows.isActive, rayTracedShadows.scene != nil else { return nil }
        return rayTracedShadows.showOnly ? rayTracedShadows.shadowView : rayTracedShadows.shaded
    }

    /// Runs once per frame after `beginCommandBuffer`, before any pass.
    func encodeRayTracedShadows() {
        let state = rayTracedShadows
        switch RayTracingScenePlan.action(
            active: state.isActive, built: state.scene != nil, current: state.isCurrent
        ) {
        case .none:
            return
        case .release:
            retireRayTracedScene()
        case .build:
            retireRayTracedScene()
            buildRayTracedScene()
        }
    }

    func bindRayTracedScene(_ table: MTL4ArgumentTable) {
        guard rayTracedPipelines != nil, let scene = rayTracedShadows.scene else { return }
        table.setResource(
            scene.instanceStructure.gpuResourceID, bufferIndex: BufferIndex.rayScene.rawValue
        )
    }

    private func retireRayTracedScene() {
        if let old = rayTracedShadows.scene {
            retireAllocations(old.allocations)
        }
        rayTracedShadows.scene = nil
        rayTracedShadows.isCurrent = false
    }

    private func buildRayTracedScene() {
        rayTracedShadows.isCurrent = true
        let instances = rayTracedInstances()
        guard !instances.isEmpty, let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        encoder.label = "Ray-Traced Shadow Structures"
        rayTracedShadows.scene = RayTracedShadowScene.build(
            instances, device: device, encoder: encoder
        )
        encoder.barrier(
            afterStages: .accelerationStructure, beforeQueueStages: .fragment,
            visibilityOptions: .device
        )
        encoder.endEncoding()
        if let built = rayTracedShadows.scene {
            residencySet.addAllocations(built.allocations)
            residencySet.commit()
        }
    }

    /// The rigid, opaque casters of the scene, and the terrain.
    private func rayTracedInstances() -> [RayTracedInstance] {
        var instances: [RayTracedInstance] = []
        for group in scene.opaque {
            var caster = RayTracingCaster()
            caster.castsShadows = group.castsShadows
            caster.isSkinned = group.mesh.isSkinned
            caster.isMorphed = group.faceMorph != nil
            for instance in group.instances {
                caster.isMoved = instance.referenceFormID != 0
                var placed = caster
                placed.castsShadows = caster.castsShadows && instance.castsShadows
                guard RayTracingScenePlan.includes(placed) else { continue }
                instances.append(RayTracedInstance(
                    mesh: group.mesh,
                    transform: instance.modelMatrix
                ))
            }
        }
        for item in scene.terrain {
            instances.append(RayTracedInstance(mesh: item.mesh, transform: item.modelMatrix))
        }
        return instances
    }
}
