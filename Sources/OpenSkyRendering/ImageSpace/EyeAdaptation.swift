// The HDR tone-mapping stage's CPU half: the eye follows the measured scene
// brightness at the `IMGS` speed, and the exposure follows the eye at the `IMGS`
// strength. The scale constants are OpenSky's own. See docs/rendering/image-space.md.

import Foundation

nonisolated public struct EyeAdaptation: Equatable, Sendable {
    /// The mean scene luminance the exposure brings the frame towards.
    public static let key: Float = 0.18
    public static let exposureRange: ClosedRange<Float> = 0.25 ... 4
    /// `IMGS` speeds are 30 to 45; divided by this they give 1.5 to 2.25 per second.
    public static let speedScale: Float = 20
    /// `IMGS` strengths are 1 to 25; strength / (strength + this) gives a 0-1 weight.
    public static let strengthHalfPoint: Float = 10

    /// Nil until the first measurement.
    public private(set) var adaptedLuminance: Float?
    public private(set) var measuredLuminance: Float?

    public init() {}

    /// Moves the eye towards `measured`. The first measurement sets it at once.
    public mutating func advance(measured: Float, speed: Float, deltaTime: Float) {
        guard measured.isFinite, measured > 0 else { return }
        measuredLuminance = measured
        guard let adapted = adaptedLuminance, speed > 0 else {
            adaptedLuminance = measured
            return
        }
        let rate = 1 - exp(-max(deltaTime, 0) * speed / Self.speedScale)
        adaptedLuminance = adapted + (measured - adapted) * rate
    }

    public mutating func reset() {
        adaptedLuminance = nil
        measuredLuminance = nil
    }

    /// The scale on scene color: above 1 in the dark, below 1 in bright light.
    public func exposure(strength: Float) -> Float {
        guard let adapted = adaptedLuminance, adapted > 0, strength > 0 else { return 1 }
        let weight = strength / (strength + Self.strengthHalfPoint)
        let exposure = pow(Self.key / adapted, weight)
        return min(max(exposure, Self.exposureRange.lowerBound), Self.exposureRange.upperBound)
    }
}

/// The tone-mapping stage's switch and its eye.
nonisolated public struct ToneMappingState: Equatable, Sendable {
    public var enabled = true
    public var eye = EyeAdaptation()

    public init() {}

    /// Whether `hdr` asks for any change: an eye that adapts, or a white point.
    public static func isActive(_ hdr: ImageSpaceHDR) -> Bool {
        hdr.eyeAdaptStrength > 0 || hdr.white > 0
    }

    /// Fixed-point steps per unit of log2 luminance in the GPU sum.
    public static let logScale: Float = 256
    /// Added to log2 luminance so every sample is positive; 2^-16 is black.
    public static let logOffset: Float = 16

    /// The mean luminance from the GPU's sum of fixed-point log2 samples.
    public static func meanLuminance(sum: UInt32, count: UInt32) -> Float? {
        guard count > 0 else { return nil }
        let meanLog = Float(sum) / Float(count) / logScale - logOffset
        return exp2(meanLog)
    }
}
