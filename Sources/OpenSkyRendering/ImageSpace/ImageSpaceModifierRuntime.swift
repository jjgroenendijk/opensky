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

    public var remaining: Float? {
        looping ? nil : max(0, adapter.playbackDuration - elapsed)
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
        looping: Bool = false
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
            looping: looping
        ))
    }

    public mutating func stopAll() {
        instances.removeAll()
    }

    /// Ages every instance and drops the one-shots past their duration.
    public mutating func advance(_ seconds: Float) {
        guard seconds.isFinite, seconds > 0 else { return }
        for index in instances.indices {
            instances[index].elapsed += seconds
        }
        instances
            .removeAll { $0.adapter.sample(elapsed: $0.elapsed, looping: $0.looping).isFinished }
    }

    /// `baseline` with every instance applied, oldest first.
    public func apply(to baseline: ImageSpaceParameters) -> ImageSpaceParameters {
        instances.reduce(baseline) { result, instance in
            result.applying(
                instance.adapter.sample(elapsed: instance.elapsed, looping: instance.looping),
                strength: instance.strength
            )
        }
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
        result.blurRadius += (sample.values[.blurRadius] ?? 0) * strength
        result.doubleVision = max(
            doubleVision,
            (sample.values[.doubleVisionStrength] ?? 0) * strength
        )
        result.radialBlur = max(radialBlur, (sample.values[.radialBlurStrength] ?? 0) * strength)
        result.tint = Self.layer(tint, over: sample.tint, strength: strength)
        result.fade = Self.layer(fade, over: sample.fade, strength: strength)
        return result
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
