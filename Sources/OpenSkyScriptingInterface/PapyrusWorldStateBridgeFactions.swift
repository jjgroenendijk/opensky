import Foundation
import OpenSkyConditions
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyWorldState

/// One pair's social answer for the natives: whether the observer is hostile, and
/// what the two factions alone make of each other. `GetFactionReaction` is the
/// faction term only (<https://ck.uesp.net/wiki/GetFactionReaction_-_Actor>).
nonisolated public struct PapyrusSocialDecision: Equatable, Sendable {
    public let isHostile: Bool
    public let factionReaction: ActorReaction

    public init(isHostile: Bool, factionReaction: ActorReaction) {
        self.isHostile = isHostile
        self.factionReaction = factionReaction
    }
}
