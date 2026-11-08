// Depth views beside the sun cascades: the precipitation occlusion view and the focus
// shadows. They render the shadow casters into a second, smaller depth array with
// rings of their own, culled on the CPU. The array is built the first time an option
// needs it, so a player with both options off pays nothing.

import Metal
import OpenSkyFormatsCore
import OpenSkyRenderCore
import OpenSkyRenderResources
import OpenSkyShaderTypes
import simd

/// One frame slot's share of the auxiliary instance and draw rings.
struct AuxiliaryShadowRings {
    let instances: any MTLBuffer
    let instanceLimit: Int
    let draws: any MTLBuffer
    let drawLimit: Int
}

/// The auxiliary depth array and its rings. Views past the ring limits drop casters.
final class AuxiliaryShadowResources {
    /// Room for the point light faces too: up to 24 views in an interior.
    static let instanceLimit = 32768
    static let drawLimit = 8192
    static let size = ShadowConstant.auxiliarySize.rawValue

    let map: any MTLTexture
    let rings: AuxiliaryShadowRings

    init?(device: any MTLDevice) {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = .depth32Float
        descriptor.width = Self.size
        descriptor.height = Self.size
        descriptor.arrayLength = ShadowConstant.auxiliarySliceCount.rawValue
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let frames = GPUFactory.maxFramesInFlight
        guard
            let map = device.makeTexture(descriptor: descriptor),
            let instances = device.makeBuffer(
                length: Self.instanceLimit * frames * MemoryLayout<InstanceTransform>.stride,
                options: .storageModeShared
            ),
            let draws = device.makeBuffer(
                length: Self.drawLimit * frames * Renderer.alignedDrawUniformsSize,
                options: .storageModeShared
            )
        else { return nil }
        map.label = "AuxiliaryShadowViews"
        instances.label = "AuxiliaryShadowInstances"
        draws.label = "AuxiliaryShadowDraws"
        self.map = map
        rings = AuxiliaryShadowRings(
            instances: instances, instanceLimit: Self.instanceLimit,
            draws: draws, drawLimit: Self.drawLimit
        )
    }

    var allocations: [any MTLAllocation] {
        [map, rings.instances, rings.draws]
    }
}

/// The array an auxiliary view draws into.
enum AuxiliaryShadowTarget {
    case auxiliary
    case pointLights
}

/// One auxiliary view this frame: its slice and its world-to-clip matrix.
struct AuxiliaryShadowView {
    let slice: Int
    let viewProjection: float4x4
    /// Layers left out, such as actors under the rain.
    let excluding: RenderLayer
    let drawsTerrain: Bool
    var target = AuxiliaryShadowTarget.auxiliary
    /// The share of the slice's side the view draws into, from its top-left corner.
    var extent: Float = 1
    /// The sphere a point light reaches. Its six faces share one caster list.
    var reach: ShadowReach?
}

/// A point light's centre and radius.
nonisolated struct ShadowReach: Equatable {
    let centre: SIMD3<Float>
    let radius: Float
}

/// The shadow groups an auxiliary view draws from.
struct AuxiliaryCasters {
    var opaque: [DrawGroup]
    var alphaTested: [DrawGroup]
}

extension Renderer {
    /// Draws this frame's auxiliary views. False only when an encoder cannot be made.
    func encodeAuxiliaryShadowViews(slot: Int, sunShadows: Bool) -> Bool {
        precipitationOcclusionView = nil
        focusShadows = FocusShadowFrame()
        pointShadows = PointShadowFrame()
        let views = auxiliaryViews(sunShadows: sunShadows)
        guard !views.isEmpty, let resources = auxiliaryShadowResources() else { return true }
        var state = ShadowPassState(
            slot: slot, base: slot * AuxiliaryShadowResources.instanceLimit,
            rings: resources.rings
        )
        var casters = AuxiliaryCasters(
            opaque: frameDrawGroups.shadowOpaque, alphaTested: frameDrawGroups.shadowAlphaTested
        )
        var castersReach: ShadowReach?
        for (number, view) in views.enumerated() {
            if view.reach != castersReach {
                castersReach = view.reach
                casters = auxiliaryCasters(reaching: view.reach)
            }
            let target = view.target == .pointLights ? pointShadowMap?.map : resources.map
            guard let target, let encoder = makeShadowEncoder(cascade: view.slice, target: target)
            else { return false }
            encoder.label = "Auxiliary Shadow View \(view.slice)"
            configureShadowEncoder(encoder)
            if view.extent < 1 {
                let side = Double(view.extent) * Double(target.width)
                encoder.setViewport(MTLViewport(
                    originX: 0, originY: 0, width: side, height: side, znear: 0, zfar: 1
                ))
            }
            let context = ShadowCascadeContext(
                cascade: ShadowCascade(
                    viewProjection: view.viewProjection,
                    splitNear: 0,
                    splitFar: 0
                ),
                frustum: Frustum(viewProjection: view.viewProjection),
                encoder: encoder,
                cullView: -1
            )
            encodeCasterGroups(
                casters.opaque, list: .opaque, in: context,
                excluding: view.excluding, state: &state
            )
            encodeCasterGroups(
                casters.alphaTested, list: .alphaTested, in: context,
                excluding: view.excluding, state: &state
            )
            if view.drawsTerrain {
                encodeShadowTerrain(in: context, state: &state)
            }
            if number == views.count - 1 {
                encoder.barrier(
                    afterStages: .fragment,
                    beforeQueueStages: [.vertex, .fragment],
                    visibilityOptions: .device
                )
            }
            encoder.endEncoding()
        }
        return true
    }

    /// The shadow groups cut down to the instances inside `reach`; all of them without one.
    private func auxiliaryCasters(reaching reach: ShadowReach?) -> AuxiliaryCasters {
        let groups = AuxiliaryCasters(
            opaque: frameDrawGroups.shadowOpaque, alphaTested: frameDrawGroups.shadowAlphaTested
        )
        guard let reach else { return groups }
        return AuxiliaryCasters(
            opaque: casters(of: groups.opaque, reaching: reach),
            alphaTested: casters(of: groups.alphaTested, reaching: reach)
        )
    }

    private func casters(of groups: [DrawGroup], reaching reach: ShadowReach) -> [DrawGroup] {
        groups.indices.compactMap { index -> DrawGroup? in
            guard groups[index].castsShadows else { return nil }
            let inside = groups[index].instances.filter { placed in
                drawn(placed).bounds.map { reach.touches($0) } ?? true
            }
            guard !inside.isEmpty else { return nil }
            let group = groups[index]
            return DrawGroup(
                mesh: group.mesh, material: group.material, faceMorph: group.faceMorph,
                instances: inside
            )
        }
    }

    /// The views the options ask for this frame; records each one for the scene pass.
    private func auxiliaryViews(sunShadows: Bool) -> [AuxiliaryShadowView] {
        var views: [AuxiliaryShadowView] = []
        if precipitationOcclusionEnabled, !precipitation.drawItems.isEmpty {
            let matrix = PrecipitationOcclusionView.matrix(
                camera: frameInput.view.position, fall: precipitation.fallDirection
            )
            precipitationOcclusionView = matrix
            views.append(AuxiliaryShadowView(
                slice: ShadowConstant.precipitationSlice.rawValue, viewProjection: matrix,
                excluding: .actors, drawsTerrain: true,
                extent: Self.precipitationOcclusionExtent
            ))
        }
        if sunShadows {
            views += focusViews()
        }
        return views + pointShadowViews()
    }

    static var precipitationOcclusionExtent: Float {
        Float(ShadowConstant.precipitationResolution.rawValue)
            / Float(AuxiliaryShadowResources.size)
    }

    /// The array, built and made resident on first use; nil when the device refuses it.
    private func auxiliaryShadowResources() -> AuxiliaryShadowResources? {
        if let auxiliaryShadow {
            return auxiliaryShadow
        }
        guard !auxiliaryShadowUnavailable else { return nil }
        guard let resources = AuxiliaryShadowResources(device: device) else {
            auxiliaryShadowUnavailable = true
            return nil
        }
        for allocation in resources.allocations {
            residencySet.addAllocation(allocation)
        }
        residencySet.commit()
        auxiliaryShadow = resources
        return resources
    }
}

nonisolated extension ShadowReach {
    /// The sphere overlaps the box: the box point nearest the centre is within the radius.
    func touches(_ bounds: ModelBounds) -> Bool {
        let nearest = simd_clamp(centre, bounds.min, bounds.max)
        return simd_distance_squared(nearest, centre) <= radius * radius
    }
}
