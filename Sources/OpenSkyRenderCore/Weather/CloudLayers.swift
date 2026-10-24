// The weather's cloud layers at one hour: texture, tint, opacity and drift per layer.
// Field layout: docs/formats/weather.md. How the layers draw: docs/engine/weather.md.

import OpenSkyFormatsESM
import simd

nonisolated public struct ResolvedCloudLayer: Equatable, Sendable {
    /// The WTHR layer index, which is also the shape index in `meshes\sky\clouds.nif`.
    public let layer: Int
    /// Relative to `textures\`, as the record spells it.
    public let texture: String
    public var color: SIMD3<Float>
    public var alpha: Float
    /// Texture coordinates per second.
    public let velocity: SIMD2<Float>

    public init(
        layer: Int, texture: String, color: SIMD3<Float>, alpha: Float, velocity: SIMD2<Float>
    ) {
        self.layer = layer
        self.texture = texture
        self.color = color
        self.alpha = alpha
        self.velocity = velocity
    }

    /// xEdit shows a speed byte as `(raw - 127) / 1270`, so 127 is still.
    public static func speed(_ raw: UInt8?) -> Float {
        guard let raw else { return 0 }
        return (Float(raw) - 127) / 1270
    }

    /// The layers that have a texture, are not disabled, and are under the LNAM limit.
    public static func layers(
        of sky: WeatherSky, weights: TimeOfDayWeights
    ) -> [ResolvedCloudLayer] {
        let limit = sky.maxCloudLayers.map(Int.init) ?? sky.cloudLayers.count
        return sky.cloudLayers.compactMap { layer in
            guard
                layer.index < limit, !layer.isDisabled,
                let texture = layer.texture, !texture.isEmpty
            else { return nil }
            let alpha = layer.alphas.map {
                weights.blend($0.sunrise, $0.day, $0.sunset, $0.night)
            } ?? 1
            let color = layer.colors.map {
                weights.blend(rgb($0.sunrise), rgb($0.day), rgb($0.sunset), rgb($0.night))
            } ?? SIMD3(repeating: 1)
            return ResolvedCloudLayer(
                layer: layer.index, texture: texture, color: color,
                alpha: simd_clamp(alpha, 0, 1),
                velocity: SIMD2(speed(layer.speedX), speed(layer.speedY))
            )
        }
    }

    func fading(_ weight: Float) -> ResolvedCloudLayer {
        var faded = self
        faded.alpha *= simd_clamp(weight, 0, 1)
        return faded
    }

    private static func rgb(_ bytes: SIMD4<UInt8>) -> SIMD3<Float> {
        SIMD3(Float(bytes.x), Float(bytes.y), Float(bytes.z)) / 255
    }
}
