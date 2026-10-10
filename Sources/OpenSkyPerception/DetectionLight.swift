// How lit a target is, from the same light the renderer shades it with: the
// ambient colour, the sun or cell directional light, and the nearby point lights
// with the shader's falloff. OpenSky's own shape; see docs/engine/detection.md.

import Foundation
import simd

/// One point light as the light sample reads it.
nonisolated public struct DetectionPointLight: Equatable, Sendable {
    public let position: SIMD3<Float>
    public let radius: Float
    public let colour: SIMD3<Float>
    public let falloffExponent: Float

    public init(
        position: SIMD3<Float>, radius: Float, colour: SIMD3<Float>, falloffExponent: Float
    ) {
        self.position = position
        self.radius = radius
        self.colour = colour
        self.falloffExponent = falloffExponent
    }
}

/// The light around one target, before it becomes a level.
nonisolated public struct DetectionLightSample: Equatable, Sendable {
    public let ambient: SIMD3<Float>
    /// The sun outdoors, or the cell's directional light indoors.
    public let directional: SIMD3<Float>
    public let pointLights: [DetectionPointLight]

    public init(
        ambient: SIMD3<Float>,
        directional: SIMD3<Float>,
        pointLights: [DetectionPointLight]
    ) {
        self.ambient = ambient
        self.directional = directional
        self.pointLights = pointLights
    }

    /// Rec. 709 luminance of the light reaching `position`. A point light uses
    /// the shader's `(1 - d / r) ^ falloff`, with no facing term, because a
    /// body is lit from every side it shows.
    public func luminance(at position: SIMD3<Float>) -> Float {
        var total = ambient + directional
        for light in pointLights {
            let radius = max(light.radius, 0.0001)
            let radial = min(max(1 - simd_distance(light.position, position) / radius, 0), 1)
            guard radial > 0 else { continue }
            total += light.colour * powf(radial, max(light.falloffExponent, 0.01))
        }
        let luminance = simd_dot(total, SIMD3(0.2126, 0.7152, 0.0722))
        return luminance.isFinite ? max(luminance, 0) : 0
    }

    /// The light level detection reads: luminance over `fullLuminance`, in 0...1.
    public func level(at position: SIMD3<Float>, fullLuminance: Float) -> Float {
        guard fullLuminance > 0, fullLuminance.isFinite else { return 1 }
        return min(luminance(at: position) / fullLuminance, 1)
    }
}
