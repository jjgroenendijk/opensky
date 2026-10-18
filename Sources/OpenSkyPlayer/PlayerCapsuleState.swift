import OpenSkyPhysics
import simd

/// The authoritative player capsule pose for one frame.
///
/// The streamer is driven with the *eye* position, and feet are eye minus
/// `PlayerCapsule.eyeHeight` only while walking, so the value is passed in
/// from `WalkController` rather than derived inside the streamer. Nil at the
/// call site means "not in walk mode, do not test".
nonisolated public struct PlayerCapsuleState: Equatable, Sendable {
    public let capsule: PlayerCapsule
    /// Capsule bottom in world space, as advanced by `WalkController`.
    public let feetPosition: SIMD3<Float>

    public init(capsule: PlayerCapsule = .standard, feetPosition: SIMD3<Float>) {
        self.capsule = capsule
        self.feetPosition = feetPosition
    }
}
