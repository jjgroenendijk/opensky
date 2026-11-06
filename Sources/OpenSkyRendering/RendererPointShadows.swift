// Cube shadows of the shadow-casting point lights. The lights nearest the camera each
// draw six 90-degree depth views into their own array; the scene shader picks the face
// and compares (docs/rendering/shadows.md#point-light-shadows).

import Metal
import OpenSkyRenderCore
import OpenSkyRenderResources
import OpenSkyShaderTypes
import simd

/// The cube face array, built the first time a shadow light is in reach.
final class PointShadowResources {
    let map: MTLTexture

    init?(device: MTLDevice) {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = .depth32Float
        descriptor.width = PointShadowMath.resolution
        descriptor.height = PointShadowMath.resolution
        descriptor.arrayLength = ShadowConstant.pointLightCount.rawValue
            * ShadowConstant.pointFaceCount.rawValue
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let map = device.makeTexture(descriptor: descriptor) else { return nil }
        map.label = "PointLightShadowFaces"
        self.map = map
    }
}

/// The shadow lights one frame drew: scene light index to its first slice.
struct PointShadowFrame {
    var firstSlices: [Int: Int] = [:]

    /// The `PointLightUniform.shadow` of scene light `index`; x is -1 without a cube.
    func uniform(sceneIndex index: Int?, radius: Float) -> SIMD4<Float> {
        guard let index, let slice = firstSlices[index] else { return SIMD4(-1, 0, 0, 0) }
        return SIMD4(
            Float(slice), PointShadowMath.nearPlane, PointShadowMath.farPlane(radius: radius),
            PointShadowMath.receiverOffset
        )
    }
}

extension Renderer {
    /// The shadow lights the last frame drew cubes for.
    public var pointShadowLightCount: Int {
        pointShadows.firstSlices.count
    }

    /// Six views for each picked shadow light; records the picks for the light uniforms.
    func pointShadowViews() -> [AuxiliaryShadowView] {
        guard pointLightShadowsEnabled, shadowRenders else { return [] }
        let candidates = scene.pointLights.indices.compactMap { index in
            let light = scene.pointLights[index]
            return light.castsShadows
                ? PointShadowCandidate(index: index, position: light.position, radius: light.radius)
                : nil
        }
        let picked = PointShadowMath.pick(
            candidates, viewer: frameInput.view.position,
            limit: ShadowConstant.pointLightCount.rawValue
        )
        guard !picked.isEmpty, pointShadowResources() != nil else { return [] }
        var views: [AuxiliaryShadowView] = []
        for (number, index) in picked.enumerated() {
            let light = scene.pointLights[index]
            let position = light.animated(at: animationTime, enabled: lightAnimationEnabled)
                .position
            let first = number * ShadowConstant.pointFaceCount.rawValue
            pointShadows.firstSlices[index] = first
            for face in 0 ..< PointShadowMath.faceCount {
                views.append(AuxiliaryShadowView(
                    slice: first + face,
                    viewProjection: PointShadowMath.viewProjection(
                        light: position, face: face, radius: light.radius
                    ),
                    excluding: [], drawsTerrain: true, target: .pointLights,
                    reach: ShadowReach(centre: position, radius: light.radius)
                ))
            }
        }
        return views
    }

    /// The face array, built and made resident on first use; nil when the device refuses it.
    private func pointShadowResources() -> PointShadowResources? {
        if let pointShadowMap {
            return pointShadowMap
        }
        guard !pointShadowUnavailable else { return nil }
        guard let resources = PointShadowResources(device: device) else {
            pointShadowUnavailable = true
            return nil
        }
        residencySet.addAllocation(resources.map)
        residencySet.commit()
        pointShadowMap = resources
        return resources
    }
}
