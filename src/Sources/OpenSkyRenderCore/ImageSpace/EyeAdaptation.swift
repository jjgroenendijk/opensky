// The HDR tone-mapping stage's CPU half: two channels follow the measured scene
// luminance at rates from the `IMGS` speed and strength, and their ratio is the
// exposure. See docs/rendering/image-space.md#hdr-tone-mapping.

import Foundation

nonisolated public struct EyeAdaptation: Equatable, Sendable {
    /// The scene luminance the character light assumes before the first measurement.
    public static let key: Float = 0.18
    /// `IMGS` speed and strength scales; the speed is a percent of the gap per 1/30 s.
    public static let speedScale: Float = 2
    public static let strengthScale: Float = 0.4
    /// No step is smaller than this, so the eye always reaches the scene.
    static let minimumStep: Float = 1 / 256
    /// Every lit pixel and the sky end times this scale (the shaders' `litOutputScale`).
    public static let sceneScale: Float = 1 / 1.2

    /// The slow channel X. The contrast pivots around it. Nil until the first measurement.
    public private(set) var adaptedLuminance: Float?
    /// The fast channel Y; the exposure is Y / X.
    public private(set) var fastLuminance: Float?
    public private(set) var measuredLuminance: Float?

    public init() {}

    /// Moves both channels towards `measured`. The first measurement sets them at once.
    public mutating func advance(measured: Float, speed: Float, strength: Float, deltaTime: Float) {
        guard measured.isFinite, measured >= 0 else { return }
        measuredLuminance = measured
        guard let slow = adaptedLuminance, let fast = fastLuminance else {
            adaptedLuminance = measured
            fastLuminance = measured
            return
        }
        let frames = 30 * max(deltaTime.isFinite ? deltaTime : 0, 0)
        let percent = 0.01 * speed * Self.speedScale
        let weight = strength * Self.strengthScale
        let slowShare = weight > 0 ? percent / weight : 1
        adaptedLuminance = Self.chase(
            slow,
            measured,
            rate: Self.rate(share: slowShare, frames: frames)
        )
        fastLuminance = Self.chase(fast, measured, rate: Self.rate(share: percent, frames: frames))
    }

    public mutating func reset() {
        adaptedLuminance = nil
        fastLuminance = nil
        measuredLuminance = nil
    }

    /// The scale on scene luminance: 1 in a steady scene, a short change after a cut.
    public var exposure: Float {
        guard let slow = adaptedLuminance, let fast = fastLuminance, slow > 0 else { return 1 }
        return fast / slow
    }

    static func rate(share: Float, frames: Float) -> Float {
        1 - pow(max(1 - share, 0), frames)
    }

    static func chase(_ previous: Float, _ target: Float, rate: Float) -> Float {
        let gap = target - previous
        let step = gap * rate
        guard step != 0 else { return previous }
        return previous + (step > 0 ? 1 : -1) * min(abs(gap), max(abs(step), minimumStep))
    }
}

/// One eye per screen quarter, as the game adapts: top left, top right, bottom left,
/// bottom right. The shader blends the four across the screen
/// (docs/rendering/image-space.md#hdr-tone-mapping).
nonisolated public struct EyeAdaptationQuarters: Equatable, Sendable {
    public static let count = 4

    public private(set) var quarters = [EyeAdaptation](repeating: EyeAdaptation(), count: count)

    public init() {}

    /// A quarter with no sample keeps its channels.
    public mutating func advance(
        measured: [Float?], speed: Float, strength: Float, deltaTime: Float
    ) {
        for (index, value) in measured.prefix(Self.count).enumerated() {
            guard let value else { continue }
            quarters[index].advance(
                measured: value, speed: speed, strength: strength, deltaTime: deltaTime
            )
        }
    }

    public mutating func reset() {
        quarters = [EyeAdaptation](repeating: EyeAdaptation(), count: Self.count)
    }

    /// The slow channel X of each quarter; `fallback` where nothing was measured yet.
    public func pivots(fallback: Float) -> SIMD4<Float> {
        SIMD4(quarters.map { $0.adaptedLuminance ?? fallback })
    }

    public var exposures: SIMD4<Float> {
        SIMD4(quarters.map(\.exposure))
    }
}

/// The tone-mapping stage's switch. The eye it adapts lives in the renderer.
nonisolated public struct ToneMappingState: Equatable, Sendable {
    public var enabled = true

    public init() {}

    /// Whether `hdr` asks for any change: an eye that adapts, or a white point.
    public static func isActive(_ hdr: ImageSpaceHDR) -> Bool {
        hdr.eyeAdaptStrength > 0 || hdr.white > 0
    }

    /// Fixed-point steps per unit of luminance in the GPU sum.
    public static let fixedPointScale: Float = 1024

    /// The plain mean luminance from the GPU's sum of fixed-point samples.
    public static func meanLuminance(sum: UInt32, count: UInt32) -> Float? {
        guard count > 0 else { return nil }
        return Float(sum) / Float(count) / fixedPointScale
    }
}
