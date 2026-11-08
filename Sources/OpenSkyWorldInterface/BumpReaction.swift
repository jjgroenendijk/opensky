import Foundation
public import OpenSkyFormatsESM
import OpenSkyGameData
import simd

/// The player touching one NPC this frame.
nonisolated public struct BumpContact: Equatable, Sendable {
    public let actor: ReferenceKey
    public let actorFeet: SIMD3<Float>
    public let playerFeet: SIMD3<Float>

    public init(actor: ReferenceKey, actorFeet: SIMD3<Float>, playerFeet: SIMD3<Float>) {
        self.actor = actor
        self.actorFeet = actorFeet
        self.playerFeet = playerFeet
    }
}

/// What the bump rule asks of the world.
nonisolated public enum BumpCommand: Equatable, Sendable {
    /// Say the bump line (`ACAC`).
    case speak(ReferenceKey)
    case move(ReferenceKey, to: SIMD3<Float>)
}
