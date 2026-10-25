// The seam the actor-value readout is written against: the engine-owned damage,
// restore and reset operations, without `GameViewController`. One snapshot value,
// so the readout comes from a single observation while the streamer mutates.

import Foundation
import OpenSkyGameData

/// One actor's values as a readout spells them.
nonisolated public struct ActorValueReadout: Equatable, Sendable {
    /// FULL name when the actor index resolves one, else the editor ID, else
    /// the FormID. Never empty, so a readout line always names something.
    public let name: String

    public init(
        name: String
    ) {
        self.name = name
    }
}

/// Who a damage or restore control applies to.
///
/// The same two selectors `EquipmentTargetSelector` offers, for the same
/// reason: the player is where the HUD meters are checked, and the nearest
/// resident actor is the only thing a hit is visible on.
nonisolated public enum ActorValueTargetSelector: Equatable, Sendable {
    case player
    /// The resident ACHR closest to the player.
    case nearestActor
}

/// One observation of the actor-value runtime.
nonisolated public struct ActorValueControlSnapshot: Equatable, Sendable {
    /// The nearest resident ACHR's values, or nil when none is loaded.
    public let nearestActor: ActorValueReadout?
    /// How many references currently carry an actor-value component, across
    /// every cell whether resident or not.
    public let runtimeActorCount: Int

    /// The reading with no runtime attached.
    public static let unavailable = ActorValueControlSnapshot(
        nearestActor: nil,
        runtimeActorCount: 0
    )

    public init(
        nearestActor: ActorValueReadout?,
        runtimeActorCount: Int
    ) {
        self.nearestActor = nearestActor
        self.runtimeActorCount = runtimeActorCount
    }
}
