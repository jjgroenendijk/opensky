// `meshes\animationdata\boundanims\anims_<project>.txt`: the root motion of each
// clip, as translation and rotation keys. Layout: docs/formats/animation-data.md.

import Foundation
import simd

/// How far a clip moves and turns its actor, relative to where the clip started.
nonisolated public struct AnimationRootMotion: Equatable, Sendable {
    public struct TranslationKey: Equatable, Sendable {
        public let time: Float
        public let offset: SIMD3<Float>
    }

    public struct RotationKey: Equatable, Sendable {
        public let time: Float
        public let rotation: simd_quatf
    }

    public let duration: Float
    public let translations: [TranslationKey]
    public let rotations: [RotationKey]

    public init(duration: Float, translations: [TranslationKey], rotations: [RotationKey]) {
        self.duration = duration
        self.translations = translations
        self.rotations = rotations
    }

    /// Before the first key the actor has not moved, so time 0 is the clip start.
    public func offset(at time: Float) -> SIMD3<Float> {
        let keys = [TranslationKey(time: 0, offset: .zero)] + translations.filter { $0.time > 0 }
        return Self.sample(keys, at: time, \.time) { start, end, fraction in
            simd_mix(start.offset, end.offset, SIMD3(repeating: fraction))
        }
    }

    public func rotation(at time: Float) -> simd_quatf {
        let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        let keys = [RotationKey(time: 0, rotation: identity)] + rotations.filter { $0.time > 0 }
        return Self.sample(keys, at: time, \.time) { simd_slerp($0.rotation, $1.rotation, $2) }
    }

    /// The turn about z at `time`, in radians.
    public func yaw(at time: Float) -> Float {
        let forward = rotation(at: time).act(SIMD3<Float>(0, 1, 0))
        return atan2(-forward.x, forward.y)
    }

    private static func sample<Key, Value>(
        _ keys: [Key], at time: Float, _ keyTime: KeyPath<Key, Float>,
        _ mix: (Key, Key, Float) -> Value
    ) -> Value {
        guard let after = keys.firstIndex(where: { $0[keyPath: keyTime] >= time }) else {
            return mix(keys[keys.count - 1], keys[keys.count - 1], 0)
        }
        guard after > 0 else { return mix(keys[0], keys[0], 0) }
        let start = keys[after - 1], end = keys[after]
        let span = end[keyPath: keyTime] - start[keyPath: keyTime]
        let fraction = span > 0 ? (time - start[keyPath: keyTime]) / span : 1
        return mix(start, end, fraction)
    }
}

nonisolated public struct AnimationMotionTable: Equatable, Sendable {
    /// Keyed by the motion index a project clip names.
    public let motions: [Int: AnimationRootMotion]

    public init(text: String) throws {
        var lines = AnimationDataLines(text)
        var motions: [Int: AnimationRootMotion] = [:]
        while !lines.isAtEnd {
            lines.skipBlank()
            let index = try lines.integer("a motion index")
            let duration = try lines.floats(1, "a duration")[0]
            let translations = try (0 ..< lines.count("a translation count")).map { _ in
                let values = try lines.floats(4, "time x y z")
                return AnimationRootMotion.TranslationKey(
                    time: values[0], offset: SIMD3(values[1], values[2], values[3])
                )
            }
            let rotations = try (0 ..< lines.count("a rotation count")).map { _ in
                let values = try lines.floats(5, "time x y z w")
                return AnimationRootMotion.RotationKey(
                    time: values[0],
                    rotation: simd_quatf(ix: values[1], iy: values[2], iz: values[3], r: values[4])
                )
            }
            // The same index appears in more than one block; the first one wins.
            motions[index] = motions[index] ?? AnimationRootMotion(
                duration: duration, translations: translations, rotations: rotations
            )
        }
        self.motions = motions
    }
}
