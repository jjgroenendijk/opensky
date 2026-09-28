import OpenSkyFormatsESM
import simd

/// One actor a swing can connect with.
nonisolated public struct MeleeTarget: Equatable, Sendable {
    /// Which reference it is, which is also the identity the once-per-swing
    /// filter and the damage application key on.
    public let key: ReferenceKey
    /// Capsule bottom, world space.
    public let feet: SIMD3<Float>
    /// Its capsule dimensions. Actors share the player's in this milestone;
    /// per-race capsules are not resolved anywhere in the engine yet.
    public let capsule: PlayerCapsule

    public init(key: ReferenceKey, feet: SIMD3<Float>, capsule: PlayerCapsule = .standard) {
        self.key = key
        self.feet = feet
        self.capsule = capsule
    }

    /// The capsule's core segment, bottom cap centre to top cap centre.
    public var segment: (first: SIMD3<Float>, second: SIMD3<Float>) {
        let radius = max(capsule.radius, 0)
        let height = max(capsule.height, radius * 2)
        return (
            feet + SIMD3(0, 0, radius),
            feet + SIMD3(0, 0, height - radius)
        )
    }
}
