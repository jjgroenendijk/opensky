// The post-process values one frame applies: an `IMGS` baseline, blended by
// weight, with active `IMAD` modifiers on top. See docs/rendering/image-space.md.

import Foundation
import OpenSkyFormatsESM
import simd

/// The `IMGS` `HNAM` values. Bloom and the light scales draw only with the HDR target on.
nonisolated public struct ImageSpaceHDR: Equatable, Sendable {
    public var eyeAdaptSpeed: Float = 0
    public var bloomBlurRadius: Float = 0
    public var bloomThreshold: Float = 0
    public var bloomScale: Float = 0
    public var receiveBloomThreshold: Float = 0
    public var white: Float = 0
    public var sunlightScale: Float = 1
    public var skyScale: Float = 1
    public var eyeAdaptStrength: Float = 0

    public init() {}

    init(_ hdr: ImageSpace.HDR) {
        eyeAdaptSpeed = hdr.eyeAdaptSpeed
        bloomBlurRadius = hdr.bloomBlurRadius
        bloomThreshold = hdr.bloomThreshold
        bloomScale = hdr.bloomScale
        receiveBloomThreshold = hdr.receiveBloomThreshold
        white = hdr.white
        sunlightScale = hdr.sunlightScale
        skyScale = hdr.skyScale
        eyeAdaptStrength = hdr.eyeAdaptStrength
    }

    /// The fields an `IMAD` HDR channel animates, by xEdit channel index.
    /// Channels 4 and 5 (target luminance) have no `IMGS` field and are not applied.
    static func field(channel: Int) -> WritableKeyPath<Self, Float>? {
        switch channel {
        case 0: \.eyeAdaptSpeed
        case 1: \.bloomBlurRadius
        case 2: \.bloomThreshold
        case 3: \.bloomScale
        case 6: \.sunlightScale
        case 7: \.skyScale
        default: nil
        }
    }

    static func blend(_ parts: [(value: Self, weight: Float)]) -> Self {
        var result = Self()
        for path in [
            \Self.eyeAdaptSpeed, \.bloomBlurRadius, \.bloomThreshold, \.bloomScale,
            \.receiveBloomThreshold, \.white, \.sunlightScale, \.skyScale, \.eyeAdaptStrength
        ] {
            result[keyPath: path] = parts.reduce(0) { $0 + $1.value[keyPath: path] * $1.weight }
        }
        return result
    }
}

nonisolated public struct ImageSpaceParameters: Equatable, Sendable {
    public var saturation: Float = 1
    public var brightness: Float = 1
    public var contrast: Float = 1
    /// RGB, then the amount in `w`.
    public var tint = SIMD4<Float>.zero
    /// RGB, then the amount in `w`. Only a modifier fades.
    public var fade = SIMD4<Float>.zero
    /// Blur radius in pixels at a 1080-pixel-high frame. Only a modifier blurs.
    public var blurRadius: Float = 0
    public var doubleVision: Float = 0
    public var radialBlur = ImageSpaceRadialBlur()
    /// `NAM4` full-screen motion blur, 0 to 1. Only a modifier sets it.
    public var motionBlur: Float = 0
    /// `DNAM` strength, focus distance, and range in world units.
    public var depthOfField = SIMD3<Float>.zero
    public var hdr = ImageSpaceHDR()

    /// No change to the frame.
    public static let neutral = Self()
    /// Strength is a share; distance and range are world units.
    static let depthOfFieldLimit = SIMD3<Float>(1, 1_000_000, 1_000_000)

    public init() {}

    public init(_ imageSpace: ImageSpace) {
        if let cinematic = imageSpace.cinematic {
            saturation = cinematic.saturation
            brightness = cinematic.brightness
            contrast = cinematic.contrast
        }
        if let tint = imageSpace.tint {
            self.tint = SIMD4(tint.color, tint.amount)
        }
        if let hdr = imageSpace.hdr {
            self.hdr = ImageSpaceHDR(hdr)
        }
        if let field = imageSpace.depthOfField {
            depthOfField = SIMD3(field.strength, field.distance, field.range)
        }
    }

    /// Whether the composite pass changes any pixel.
    public var isNeutral: Bool {
        saturation == 1 && brightness == 1 && contrast == 1 && tint.w <= 0 && fade.w <= 0
            && blurRadius <= 0 && doubleVision <= 0 && radialBlur.strength <= 0 && motionBlur <= 0
    }

    /// The weighted sum of `parts`. Weights are normalized, so they need not add up to 1.
    public static func blend(_ parts: [(value: Self, weight: Float)]) -> Self {
        let total = parts.reduce(0) { $0 + max(0, $1.weight) }
        guard total > 0 else { return .neutral }
        let normalized = parts.map { (value: $0.value, weight: max(0, $0.weight) / total) }
        func sum(_ path: KeyPath<Self, Float>) -> Float {
            normalized.reduce(0) { $0 + $1.value[keyPath: path] * $1.weight }
        }
        func sum<Vector: SIMD>(_ path: KeyPath<Self, Vector>) -> Vector
            where Vector.Scalar == Float
        {
            normalized.reduce(.zero) { $0 + $1.value[keyPath: path] * $1.weight }
        }
        var result = Self()
        result.saturation = sum(\.saturation)
        result.brightness = sum(\.brightness)
        result.contrast = sum(\.contrast)
        result.tint = sum(\.tint)
        result.fade = sum(\.fade)
        result.blurRadius = sum(\.blurRadius)
        result.doubleVision = sum(\.doubleVision)
        result.radialBlur = normalized.max { $0.weight < $1.weight }?.value.radialBlur
            ?? ImageSpaceRadialBlur()
        result.radialBlur.strength = sum(\.radialBlur.strength)
        result.motionBlur = sum(\.motionBlur)
        result.depthOfField = sum(\.depthOfField)
        result.hdr = ImageSpaceHDR
            .blend(normalized.map { (value: $0.value.hdr, weight: $0.weight) })
        return result
    }

    /// Clamped to what the composite shader can show without blowing out or inverting.
    public var clampedForDisplay: Self {
        var result = self
        result.saturation = simd_clamp(saturation, 0, 4)
        result.brightness = simd_clamp(brightness, 0, 4)
        result.contrast = simd_clamp(contrast, 0, 4)
        result.tint = simd_clamp(tint, .zero, SIMD4(repeating: 1))
        result.fade = simd_clamp(fade, .zero, SIMD4(repeating: 1))
        result.blurRadius = simd_clamp(blurRadius, 0, 32)
        result.doubleVision = simd_clamp(doubleVision, 0, 1)
        result.radialBlur = radialBlur.clamped
        result.motionBlur = motionBlur.isFinite ? simd_clamp(motionBlur, 0, 1) : 0
        result.depthOfField = simd_clamp(depthOfField, .zero, Self.depthOfFieldLimit)
        return result
    }
}

/// The radial blur of the strongest modifier: a blur along lines from `center` that
/// rises from `start` and falls after `downStart`. See docs/rendering/image-space.md.
nonisolated public struct ImageSpaceRadialBlur: Equatable, Sendable {
    public var strength: Float = 0
    public var rampUp: Float = 0
    /// A share of the centre-to-corner distance.
    public var start: Float = 0
    public var rampDown: Float = 0
    /// Not used when it is not past `start`.
    public var downStart: Float = 0
    /// In screen units, 0 to 1 from the top left.
    public var center = SIMD2<Float>(0.5, 0.5)

    public init() {}

    /// CK wiki: "Str" 2.5 is moderate and 5 strong, so 10 is the cap.
    var clamped: Self {
        var result = self
        func finite(_ value: Float, _ upper: Float) -> Float {
            value.isFinite ? simd_clamp(value, 0, upper) : 0
        }
        result.strength = finite(strength, 10)
        result.rampUp = finite(rampUp, 100)
        result.start = finite(start, 1)
        result.rampDown = finite(rampDown, 100)
        result.downStart = finite(downStart, 1)
        result.center = SIMD2(finite(center.x, 1), finite(center.y, 1))
        return result
    }

    /// The share of the full blur at `radius`, the centre-to-corner share.
    public func weight(atRadius radius: Float) -> Float {
        let rising = simd_clamp((radius - start) * rampUp, 0, 1)
        guard downStart > start else { return rising }
        return rising * simd_clamp(1 - (radius - downStart) * rampDown, 0, 1)
    }
}
