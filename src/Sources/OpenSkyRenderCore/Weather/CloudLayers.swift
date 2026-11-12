// The weather's cloud layers at one hour: texture, tint, and opacity per layer, the drift
// speed per layer index, and the drift offset the frame keeps.
// Field layout: docs/formats/weather.md. How the layers draw: docs/engine/weather.md.

public import OpenSkyFormatsESM
import simd

nonisolated public struct ResolvedCloudLayer: Equatable, Sendable {
    /// The WTHR layer index, which is also the shape index in `meshes\sky\clouds.nif`.
    public let layer: Int
    /// Relative to `textures\`, as the record spells it.
    public let texture: String
    public var color: SIMD3<Float>
    public var alpha: Float

    public init(layer: Int, texture: String, color: SIMD3<Float>, alpha: Float) {
        self.layer = layer
        self.texture = texture
        self.color = color
        self.alpha = alpha
    }

    /// Texture units per second: a tenth of `fWeatherCloudSpeedMax` times `raw / 127 - 1`,
    /// so 127 is still (docs/engine/weather.md#clouds).
    public static func speed(_ raw: UInt8?, speedMax: Float) -> Float {
        guard let raw else { return 0 }
        return 0.1 * speedMax * (Float(raw) / 127 - 1)
    }

    /// One drift per layer index, textured or not: the other weather of a change may
    /// draw that index.
    public static func velocities(of sky: WeatherSky, speedMax: Float) -> [SIMD2<Float>] {
        var velocities = [SIMD2<Float>](repeating: .zero, count: sky.cloudLayers.count)
        for layer in sky.cloudLayers where velocities.indices.contains(layer.index) {
            velocities[layer.index] = SIMD2(
                speed(layer.speedX, speedMax: speedMax), speed(layer.speedY, speedMax: speedMax)
            )
        }
        return velocities
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
                alpha: simd_clamp(alpha, 0, 1)
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

/// The texture offset of each cloud layer index. Both weathers of a change draw a layer
/// index at one offset, which moves at their blended speed.
nonisolated public struct CloudDrift: Equatable, Sendable {
    public private(set) var offsets: [SIMD2<Float>] = []

    public init() {}

    public func offset(layer: Int) -> SIMD2<Float> {
        offsets.indices.contains(layer) ? offsets[layer] : .zero
    }

    public mutating func advance(seconds: Float, velocities: [SIMD2<Float>]) {
        guard seconds > 0 else { return }
        grow(to: velocities.count)
        for (layer, velocity) in velocities.enumerated() {
            offsets[layer] = Self.wrapped(offsets[layer] + velocity * seconds)
        }
    }

    /// The offsets after `seconds` at constant `velocities`, for a frame rendered at an
    /// exact time.
    public mutating func seek(seconds: Float, velocities: [SIMD2<Float>]) {
        offsets = velocities.map { Self.wrapped($0 * seconds) }
    }

    private mutating func grow(to count: Int) {
        if offsets.count < count {
            offsets += Array(repeating: .zero, count: count - offsets.count)
        }
    }

    /// Wrapped to one texture repeat, so a long session keeps float precision.
    private static func wrapped(_ offset: SIMD2<Float>) -> SIMD2<Float> {
        offset - offset.rounded(.down)
    }
}
