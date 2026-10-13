// Samples NIF animation keys at a time. Every key type is sampled linearly:
// quadratic and TBC tangents are read past (docs/formats/nif-sequences.md).

import Foundation
import simd

nonisolated public enum NIFKeySampler {
    /// The keyed value at `time`: the first key before it, the last key after it.
    /// Nil for no keys.
    public static func sample<Value>(
        _ keys: [NIFKey<Value>],
        at time: Float,
        mix: (Value, Value, Float) -> Value
    ) -> Value? {
        guard let first = keys.first, let last = keys.last else { return nil }
        guard time > first.time else { return first.value }
        guard time < last.time else { return last.value }
        let upper = keys.firstIndex { $0.time >= time } ?? keys.count - 1
        let lower = keys[upper - 1]
        let span = keys[upper].time - lower.time
        let fraction = span > 0 ? (time - lower.time) / span : 1
        return mix(lower.value, keys[upper].value, fraction)
    }

    public static func float(_ keys: [NIFKey<Float>], at time: Float) -> Float? {
        sample(keys, at: time) { $0 + ($1 - $0) * $2 }
    }

    public static func vector(_ keys: [NIFKey<SIMD3<Float>>], at time: Float) -> SIMD3<Float>? {
        sample(keys, at: time) { simd_mix($0, $1, SIMD3(repeating: $2)) }
    }

    public static func rotation(_ keys: [NIFKey<simd_quatf>], at time: Float) -> simd_quatf? {
        sample(keys, at: time) { simd_slerp($0, $1, $2) }
    }

    /// A bool key holds until the next key.
    public static func step(_ keys: [NIFKey<Bool>], at time: Float) -> Bool? {
        sample(keys, at: time) { from, to, fraction in fraction >= 1 ? to : from }
    }
}
