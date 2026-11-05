// The running `IMAD` instances: start by record and strength, age on the game
// clock, drop at the end of the duration, and fold over the baseline image
// space in start order. Pure. See docs/rendering/image-space.md.

import Foundation
import OpenSkyFormatsESM
import simd

nonisolated public struct ImageSpaceModifierInstance: Equatable, Sendable {
    public let key: ReferenceKey
    public let name: String
    public let adapter: ImageSpaceAdapter
    /// 0 to 1. Scales how far each envelope moves the baseline.
    public let strength: Float
    public let looping: Bool
    public internal(set) var elapsed: Float = 0
    /// Seconds the instance takes to reach its strength; 0 starts at full strength.
    public let fadeIn: Float
    /// Set by a timed removal: the elapsed time it began and how long it lasts.
    public internal(set) var fadeOut: (start: Float, duration: Float)?

    public var remaining: Float? {
        if let fadeOut {
            return max(0, fadeOut.start + fadeOut.duration - elapsed)
        }
        return looping ? nil : max(0, adapter.playbackDuration - elapsed)
    }

    /// `strength` times the fade-in and fade-out weights now.
    public var currentStrength: Float {
        var weight: Float = fadeIn > 0 ? min(elapsed / fadeIn, 1) : 1
        if let fadeOut {
            let gone = fadeOut.duration > 0 ? (elapsed - fadeOut.start) / fadeOut.duration : 1
            weight *= simd_clamp(1 - gone, 0, 1)
        }
        return strength * weight
    }

    var isFadedOut: Bool {
        guard let fadeOut else { return false }
        return elapsed >= fadeOut.start + fadeOut.duration
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key && lhs.name == rhs.name && lhs.adapter == rhs.adapter
            && lhs.strength == rhs.strength && lhs.looping == rhs.looping
            && lhs.elapsed == rhs.elapsed && lhs.fadeIn == rhs.fadeIn
            && lhs.fadeOut?.start == rhs.fadeOut?.start
            && lhs.fadeOut?.duration == rhs.fadeOut?.duration
    }
}

nonisolated public struct ImageSpaceModifierRuntime: Equatable, Sendable {
    /// More at once is noise; the oldest goes first. OpenSky's value.
    public static let maximumInstances = 16

    public private(set) var instances: [ImageSpaceModifierInstance] = []

    public init() {}

    /// Starts `adapter`. A one-shot start of a record already running restarts it,
    /// so a burst of hits does not stack the same flash.
    public mutating func start(
        _ adapter: ImageSpaceAdapter,
        key: ReferenceKey,
        strength: Float = 1,
        looping: Bool = false,
        fadeIn: Float = 0
    ) {
        if !looping {
            instances.removeAll { $0.key == key && !$0.looping }
        }
        if instances.count >= Self.maximumInstances {
            instances.removeFirst(instances.count - Self.maximumInstances + 1)
        }
        instances.append(ImageSpaceModifierInstance(
            key: key,
            name: adapter.editorID ?? key.description,
            adapter: adapter,
            strength: strength.isFinite ? simd_clamp(strength, 0, 1) : 0,
            looping: looping,
            fadeIn: fadeIn.isFinite ? max(fadeIn, 0) : 0
        ))
    }

    /// Stops every running instance of the record `key`, at once or over `fadeOut` seconds.
    public mutating func stop(key: ReferenceKey, fadeOut: Float = 0) {
        guard fadeOut.isFinite, fadeOut > 0 else {
            instances.removeAll { $0.key == key }
            return
        }
        for index in instances.indices where instances[index].key == key {
            let current = instances[index]
            guard current.fadeOut == nil else { continue }
            instances[index].fadeOut = (current.elapsed, fadeOut)
        }
    }

    /// Ages every instance and drops the one-shots past their duration.
    public mutating func advance(_ seconds: Float) {
        guard seconds.isFinite, seconds > 0 else { return }
        for index in instances.indices {
            instances[index].elapsed += seconds
        }
        instances.removeAll {
            $0.isFadedOut || $0.adapter.sample(elapsed: $0.elapsed, looping: $0.looping).isFinished
        }
    }

    /// `baseline` with every instance applied, oldest first. The tint is the
    /// alpha-weighted average over all of them, so it does not depend on the order.
    public func apply(to baseline: ImageSpaceParameters) -> ImageSpaceParameters {
        let samples = instances.map {
            ($0.adapter.sample(elapsed: $0.elapsed, looping: $0.looping), $0.currentStrength)
        }
        var result = samples.reduce(baseline) { $0.applying($1.0, strength: $1.1) }
        result.tint = ImageSpaceParameters.averageTint(
            [baseline.tint] + samples.compactMap { sample, strength in
                sample.tint.map { SIMD4($0.x, $0.y, $0.z, $0.w * strength) }
            }
        )
        return result
    }
}

nonisolated extension ImageSpaceParameters {
    /// One modifier sample over these values. A multiply envelope scales the value and
    /// an add envelope adds to it, both weighted by `strength`.
    public func applying(_ sample: ImageSpaceAdapterSample, strength: Float) -> Self {
        var result = self
        func animate(_ path: WritableKeyPath<Self, Float>, multiply: Float?, add: Float?) {
            let scale = 1 + ((multiply ?? 1) - 1) * strength
            result[keyPath: path] = result[keyPath: path] * scale + (add ?? 0) * strength
        }
        let cinematic: [WritableKeyPath<Self, Float>] = [\.saturation, \.brightness, \.contrast]
        for (index, path) in cinematic.enumerated() {
            animate(
                path,
                multiply: sample.values[.cinematic(index: index, add: false)],
                add: sample.values[.cinematic(index: index, add: true)]
            )
        }
        let hdr: WritableKeyPath<Self, ImageSpaceHDR> = \.hdr
        for channel in 0 ..< 8 {
            guard let field = ImageSpaceHDR.field(channel: channel) else { continue }
            animate(
                hdr.appending(path: field),
                multiply: sample.values[.hdr(index: channel, add: false)],
                add: sample.values[.hdr(index: channel, add: true)]
            )
        }
        result.blurRadius = max(blurRadius, (sample.values[.blurRadius] ?? 0) * strength)
        result.motionBlur = max(motionBlur, (sample.values[.motionBlurStrength] ?? 0) * strength)
        result.doubleVision = max(
            doubleVision,
            (sample.values[.doubleVisionStrength] ?? 0) * strength
        )
        result.radialBlur = radialBlur.strongest(sample, strength: strength)
        let focus: [ImageSpaceChannel] = [
            .depthOfFieldStrength, .depthOfFieldDistance, .depthOfFieldRange
        ]
        for (index, channel) in focus.enumerated() {
            guard let value = sample.values[channel] else { continue }
            result.depthOfField[index] += (value - depthOfField[index]) * strength
        }
        if
            sample.values[.depthOfFieldStrength] != nil, strength > 0,
            let flags = sample.depthOfFieldFlags
        {
            result.depthOfFieldSides = DepthOfFieldSides(flags: flags)
            result.depthOfFieldKeepsSkySharp = flags & 0x04 != 0
        }
        if let color = sample.tint {
            result.tint = Self.averageTint([
                tint,
                SIMD4(color.x, color.y, color.z, color.w * strength)
            ])
        }
        result.fade = Self.layer(fade, over: sample.fade, strength: strength)
        return result
    }

    /// CK wiki "ImageSpace Modifiers": the RGB is the average weighted by alpha, and the
    /// alpha is the highest one.
    static func averageTint(_ tints: [SIMD4<Float>]) -> SIMD4<Float> {
        let weight = tints.reduce(0) { $0 + max($1.w, 0) }
        guard weight > 0 else { return tints.first ?? .zero }
        let rgb = tints.reduce(SIMD3<Float>.zero) {
            $0 + SIMD3($1.x, $1.y, $1.z) * max($1.w, 0)
        } / weight
        return SIMD4(rgb, tints.map(\.w).max() ?? 0)
    }

    /// Lays a modifier color over a base color. Amounts combine like alpha.
    static func layer(
        _ base: SIMD4<Float>,
        over color: SIMD4<Float>?,
        strength: Float
    ) -> SIMD4<Float> {
        guard let color else { return base }
        let amount = simd_clamp(color.w * strength, 0, 1)
        guard amount > 0 else { return base }
        let combined = base.w + amount * (1 - base.w)
        let rgb = simd_mix(
            SIMD3(base.x, base.y, base.z),
            SIMD3(color.x, color.y, color.z),
            SIMD3(repeating: combined > 0 ? amount / combined : 1)
        )
        return SIMD4(rgb, combined)
    }
}

nonisolated extension ImageSpaceRadialBlur {
    /// The CK wiki keeps the highest blur, so the strongest modifier gives the whole shape.
    func strongest(_ sample: ImageSpaceAdapterSample, strength scale: Float) -> Self {
        let candidate = (sample.values[.radialBlurStrength] ?? 0) * scale
        guard candidate > strength else { return self }
        var result = Self()
        result.strength = candidate
        result.rampUp = sample.values[.radialBlurRampUp] ?? 0
        result.start = sample.values[.radialBlurStart] ?? 0
        result.rampDown = sample.values[.radialBlurRampDown] ?? 0
        result.downStart = sample.values[.radialBlurDownStart] ?? 0
        result.center = sample.radialBlurCenter ?? result.center
        return result
    }
}
