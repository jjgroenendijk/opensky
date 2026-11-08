import Foundation
import OpenSkyAudio
public import OpenSkyFormatsESM
import simd

/// What a resolved hit impact turns into. The melee counterpart of
/// `ResolvedFootstep`, and deliberately the same shape.
nonisolated public struct ResolvedMeleeImpact: Equatable, Sendable {
    /// The SNDR to play. Never null: a resolution with no sound is reported as
    /// nil instead.
    public let sound: FormID
    /// The IPCT, for its model and decal.
    public let impact: Impact?
    /// The actor struck, so a blood decal can find the ground under it.
    public var target: ReferenceKey?
    /// The struck surface's normal; nil for an actor.
    public var surfaceNormal: SIMD3<Float>?

    public init(
        sound: FormID,
        impact: Impact? = nil,
        target: ReferenceKey? = nil,
        surfaceNormal: SIMD3<Float>? = nil
    ) {
        self.sound = sound
        self.impact = impact
        self.target = target
        self.surfaceNormal = surfaceNormal
    }
}
