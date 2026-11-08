// Shader values that a mesh animates on its own clock: UV scroll, alpha, emissive
// strength and colour, and the effect falloff. Source: NIF shader property controllers
// (docs/formats/nif-controllers.md#shader-property-controllers).

import Foundation
import simd

/// nif.xml `NiTimeController` timing: how seconds map into the key range.
nonisolated public struct ControllerClock: Hashable, Sendable {
    public enum Cycle: UInt16, Hashable, Sendable {
        case loop = 0
        case reverse = 1
        case clamp = 2
    }

    public let cycle: Cycle
    public let frequency: Float
    public let phase: Float
    public let startTime: Float
    public let stopTime: Float

    public init(cycle: Cycle, frequency: Float, phase: Float, startTime: Float, stopTime: Float) {
        self.cycle = cycle
        self.frequency = frequency
        self.phase = phase
        self.startTime = startTime
        self.stopTime = stopTime
    }

    /// Maps a playback time in seconds into the key range.
    public func time(at seconds: Float) -> Float {
        let scaled = seconds * frequency + phase
        let span = stopTime - startTime
        guard span.isFinite, span > 0 else { return scaled }
        let offset = scaled - startTime
        switch cycle {
        case .clamp:
            return simd_clamp(scaled, startTime, stopTime)
        case .loop:
            return startTime + Self.positiveRemainder(offset, span)
        case .reverse:
            let folded = Self.positiveRemainder(offset, span * 2)
            return startTime + (folded <= span ? folded : span * 2 - folded)
        }
    }

    private static func positiveRemainder(_ value: Float, _ divisor: Float) -> Float {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder < 0 ? remainder + divisor : remainder
    }
}

nonisolated public struct MaterialAnimation: Hashable, Sendable {
    /// The material value a track drives.
    public enum Target: UInt8, Hashable, Sendable, CaseIterable {
        case uOffset, vOffset, uScale, vScale
        case alpha
        case emissiveMultiple
        case emissiveColor
        case falloffStartAngle, falloffStopAngle, falloffStartOpacity, falloffStopOpacity
        case glossiness, specularStrength, specularColor
        case environmentScale, refractionStrength
    }

    /// One controller: linear keys on its own clock. A float track keeps its value in `x`.
    public struct Track: Hashable, Sendable {
        public let target: Target
        public let clock: ControllerClock
        public let times: [Float]
        public let values: [SIMD3<Float>]

        public init(
            target: Target,
            clock: ControllerClock,
            times: [Float],
            values: [SIMD3<Float>]
        ) {
            self.target = target
            self.clock = clock
            self.times = times
            self.values = values
        }

        /// The keyed value at `seconds`: the first key before the range, the last after it.
        public func value(at seconds: Float) -> SIMD3<Float>? {
            guard let first = values.first, let last = values.last, times.count == values.count
            else { return nil }
            let time = clock.time(at: seconds)
            guard time > times[0] else { return first }
            guard time < times[times.count - 1] else { return last }
            let upper = times.firstIndex { $0 >= time } ?? times.count - 1
            let span = times[upper] - times[upper - 1]
            let fraction = span > 0 ? (time - times[upper - 1]) / span : 1
            return simd_mix(values[upper - 1], values[upper], SIMD3(repeating: fraction))
        }
    }

    public let tracks: [Track]

    public init(tracks: [Track]) {
        self.tracks = tracks
    }

    /// The material with every track applied at `seconds`.
    public func apply(to material: Material, at seconds: Float) -> Material {
        var values = AnimatedValues(material)
        for track in tracks {
            guard let value = track.value(at: seconds) else { continue }
            values.set(track.target, value)
        }
        return values.material(from: material)
    }
}

/// The animatable part of a material, edited in place, then written back.
nonisolated private struct AnimatedValues {
    var uvOffset: SIMD2<Float>
    var uvScale: SIMD2<Float>
    var alpha: Float
    var glossiness: Float
    var specularColor: SIMD3<Float>
    var specularStrength: Float
    var effect: EffectShading?
    var shading: SurfaceShading

    init(_ material: Material) {
        uvOffset = material.uvOffset
        uvScale = material.uvScale
        alpha = material.alpha
        glossiness = material.glossiness
        specularColor = material.specularColor
        specularStrength = material.specularStrength
        effect = material.effect
        shading = material.shading
    }

    mutating func set(_ target: MaterialAnimation.Target, _ value: SIMD3<Float>) {
        switch target {
        case .uOffset: uvOffset.x = value.x
        case .vOffset: uvOffset.y = value.x
        case .uScale: uvScale.x = value.x
        case .vScale: uvScale.y = value.x
        case .glossiness: glossiness = value.x
        case .specularStrength: specularStrength = value.x
        case .specularColor: specularColor = value
        case .environmentScale: shading.environmentScale = value.x
        case .refractionStrength: shading.refractionStrength = value.x
        default: setShading(target, value)
        }
    }

    /// Alpha, emissive, and falloff: an effect shape keeps them in its effect shading.
    private mutating func setShading(_ target: MaterialAnimation.Target, _ value: SIMD3<Float>) {
        switch target {
        case .alpha: setAlpha(value.x)
        case .emissiveMultiple: setEmissiveMultiple(value.x)
        case .emissiveColor: setEmissiveColor(value)
        case .falloffStartAngle: setFalloff(0, value.x)
        case .falloffStopAngle: setFalloff(1, value.x)
        case .falloffStartOpacity: setFalloff(2, value.x)
        case .falloffStopOpacity: setFalloff(3, value.x)
        default: return
        }
    }

    /// An effect shape keeps its alpha in the base colour; a lit shape in the material.
    private mutating func setAlpha(_ value: Float) {
        if effect != nil {
            effect?.baseColor.w = value
        } else {
            alpha = value
        }
    }

    private mutating func setEmissiveMultiple(_ value: Float) {
        if effect != nil {
            effect?.baseColorScale = value
        } else {
            shading.emissiveMultiple = value
        }
    }

    private mutating func setEmissiveColor(_ value: SIMD3<Float>) {
        if let base = effect?.baseColor {
            effect?.baseColor = SIMD4(value, base.w)
        } else {
            shading.emissiveColor = value
        }
    }

    private mutating func setFalloff(_ index: Int, _ value: Float) {
        guard effect != nil else { return }
        var falloff = effect?.falloff ?? SIMD4(1, 0, 1, 1)
        falloff[index] = value
        effect?.falloff = falloff
    }

    func material(from base: Material) -> Material {
        Material(
            diffuseTexture: base.diffuseTexture, normalTexture: base.normalTexture,
            uvOffset: uvOffset, uvScale: uvScale, alpha: alpha, glossiness: glossiness,
            specularColor: specularColor, specularStrength: specularStrength,
            doubleSided: base.doubleSided, alphaBlend: base.alphaBlend,
            alphaTestThreshold: base.alphaTestThreshold, additiveBlend: base.additiveBlend,
            effect: effect, waterSurface: base.waterSurface, tintTexture: base.tintTexture,
            tintsSkin: base.tintsSkin, shading: shading, drawState: base.drawState,
            animation: base.animation
        )
    }
}
