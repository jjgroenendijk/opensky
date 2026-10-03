// Samples `IMAD` envelopes at a time: clamped at the ends, linear between keys.
// See docs/formats/image-spaces.md, section "Sampling".

import Foundation
import OpenSkyFormatsESM
import simd

nonisolated public enum ImageSpaceEnvelope {
    /// The value at `time`, or nil for an empty envelope. Keys need not be sorted.
    public static func sample(_ keys: [ImageSpaceKeyframe], at time: Float) -> Float? {
        interpolate(keys.map { ($0.time, SIMD4($0.value, 0, 0, 0)) }, at: time)?.x
    }

    public static func sample(_ keys: [ImageSpaceColorKeyframe], at time: Float) -> SIMD4<Float>? {
        interpolate(keys.map { ($0.time, $0.color) }, at: time)
    }

    private static func interpolate(
        _ keys: [(time: Float, value: SIMD4<Float>)],
        at time: Float
    ) -> SIMD4<Float>? {
        let sorted = keys.filter(\.time.isFinite).sorted { $0.time < $1.time }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        guard time > first.time else { return first.value }
        guard time < last.time else { return last.value }
        for (lower, upper) in zip(sorted, sorted.dropFirst()) where time <= upper.time {
            let span = upper.time - lower.time
            guard span > 0 else { return upper.value }
            return simd_mix(lower.value, upper.value, SIMD4(repeating: (time - lower.time) / span))
        }
        return last.value
    }
}

/// Every present channel of one modifier at one moment.
nonisolated public struct ImageSpaceAdapterSample: Equatable, Sendable {
    /// The key time the channels were read at: a fraction or seconds, as the record spells it.
    public let time: Float
    public let values: [ImageSpaceChannel: Float]
    /// RGB, then the amount in `w`.
    public let tint: SIMD4<Float>?
    public let fade: SIMD4<Float>?
    /// A one-shot modifier past its duration.
    public let isFinished: Bool
}

nonisolated extension ImageSpaceAdapter {
    /// The shortest duration a modifier plays, so a zero `DNAM` duration still shows a frame.
    public static let minimumDuration: Float = 0.1

    /// An animatable modifier spells key times as a fraction of its duration; one that is
    /// not animatable spells them in seconds. Read from the install's key times.
    public var keyTimesAreFractions: Bool {
        header?.isAnimatable ?? true
    }

    /// `DNAM` duration, at least `minimumDuration`.
    public var duration: Float {
        guard
            let duration = header?.duration,
            duration.isFinite else { return Self.minimumDuration }
        return max(duration, Self.minimumDuration)
    }

    /// Seconds the modifier runs: its duration, or for second-based keys the last key
    /// time plus the duration it then holds.
    public var playbackDuration: Float {
        guard !keyTimesAreFractions else { return duration }
        let times = envelopes.values.flatMap { $0.map(\.time) } + tint.map(\.time) + fade
            .map(\.time)
        return (times.filter(\.isFinite).max() ?? 0) + duration
    }

    /// The channels at `elapsed` seconds since start. A looping modifier wraps over
    /// `playbackDuration`.
    public func sample(elapsed: Float, looping: Bool = false) -> ImageSpaceAdapterSample {
        let total = playbackDuration
        let elapsed = elapsed.isFinite ? max(0, elapsed) : 0
        let finished = !looping && elapsed > total
        let local = looping ? elapsed.truncatingRemainder(dividingBy: total) : min(elapsed, total)
        let time = keyTimesAreFractions ? local / duration : local
        var values: [ImageSpaceChannel: Float] = [:]
        for (channel, keys) in envelopes {
            values[channel] = ImageSpaceEnvelope.sample(keys, at: time)
        }
        return ImageSpaceAdapterSample(
            time: time,
            values: values,
            tint: ImageSpaceEnvelope.sample(tint, at: time),
            fade: ImageSpaceEnvelope.sample(fade, at: time),
            isFinished: finished
        )
    }
}
