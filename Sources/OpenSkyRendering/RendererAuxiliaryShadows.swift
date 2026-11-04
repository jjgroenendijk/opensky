// Depth views beside the sun cascades: the precipitation occlusion view and the focus
// shadows. They render the shadow casters into a second, smaller depth array with
// rings of their own, culled on the CPU. The array is built the first time an option
// needs it, so a player with both options off pays nothing.

import Metal
import OpenSkyRenderCore
import OpenSkyRenderResources
import OpenSkyShaderTypes
import simd

/// One frame slot's share of the auxiliary instance and draw rings.
struct AuxiliaryShadowRings {
    let instances: MTLBuffer
    let instanceLimit: Int
    let draws: MTLBuffer
    let drawLimit: Int
}

/// The auxiliary depth array and its rings. Views past the ring limits drop casters.
final class AuxiliaryShadowResources {
    static let instanceLimit = 16384
    static let drawLimit = 4096

    let map: MTLTexture
    let rings: AuxiliaryShadowRings

    init?(device: MTLDevice) {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = .depth32Float
        descriptor.width = PrecipitationOcclusionView.resolution
        descriptor.height = PrecipitationOcclusionView.resolution
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

    var allocations: [MTLAllocation] {
        [map, rings.instances, rings.draws]
    }
}

/// One auxiliary view this frame: its slice and its world-to-clip matrix.
struct AuxiliaryShadowView {
    let slice: Int
    let viewProjection: float4x4
    /// Layers left out, such as actors under the rain.
    let excluding: RenderLayer
}

extension Renderer {
    /// Draws this frame's auxiliary views. False only when an encoder cannot be made.
    func encodeAuxiliaryShadowViews(slot: Int) -> Bool {
        precipitationOcclusionView = nil
        let views = auxiliaryViews()
        guard !views.isEmpty, let resources = auxiliaryShadowResources() else { return true }
        var state = ShadowPassState(
            slot: slot, base: slot * AuxiliaryShadowResources.instanceLimit,
            rings: resources.rings
        )
        for (number, view) in views.enumerated() {
            guard let encoder = makeShadowEncoder(cascade: view.slice, target: resources.map)
            else { return false }
            encoder.label = "Auxiliary Shadow View \(view.slice)"
            configureShadowEncoder(encoder)
            let context = ShadowCascadeContext(
                cascade: ShadowCascade(viewProjection: view.viewProjection, splitNear: 0, splitFar: 0),
                frustum: Frustum(viewProjection: view.viewProjection),
                encoder: encoder,
                cullView: -1
            )
            encodeCasterGroups(
                frameDrawGroups.shadowOpaque, list: .opaque, in: context,
                excluding: view.excluding, state: &state
            )
            encodeCasterGroups(
                frameDrawGroups.shadowAlphaTested, list: .alphaTested, in: context,
                excluding: view.excluding, state: &state
            )
            encodeShadowTerrain(in: context, state: &state)
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

    /// The views the options ask for this frame; records each one for the scene pass.
    private func auxiliaryViews() -> [AuxiliaryShadowView] {
        var views: [AuxiliaryShadowView] = []
        if precipitationOcclusionEnabled, !precipitation.drawItems.isEmpty {
            let matrix = PrecipitationOcclusionView.matrix(camera: frameInput.view.position)
            precipitationOcclusionView = matrix
            views.append(AuxiliaryShadowView(
                slice: ShadowConstant.precipitationSlice.rawValue, viewProjection: matrix,
                excluding: .actors
            ))
        }
        return views
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
