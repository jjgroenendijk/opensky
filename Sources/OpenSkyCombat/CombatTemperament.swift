// How an actor's Confidence decides whether it engages or breaks off, from how strong
// it is beside its target (<https://ck.uesp.net/wiki/AI_Data_Tab>). The wiki words each
// level; the strength thresholds below are OpenSky's reading of them
// (docs/engine/combat-behavior.md, "Confidence and Assistance").

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public struct CombatTemperament: Equatable, Sendable {
    /// `Confidence` actor value: 0 cowardly through 4 foolhardy.
    public var confidence: Float
    /// A per-actor nudge in `fCombatConfidenceModifierMin` to `...Max`, so a crowd
    /// of one record does not break off at one moment.
    public var modifier: Float
    /// Health fraction over the target's, scaled by the square root of the level ratio.
    public var strengthRatio: Float

    public init(confidence: Float, modifier: Float = 0, strengthRatio: Float) {
        self.confidence = confidence
        self.modifier = modifier
        self.strengthRatio = strengthRatio
    }

    public static let modifierRange: ClosedRange<Float> = -0.5 ... 0.5

    /// Cowardly "will always flee", foolhardy "will never flee". Between them the actor
    /// breaks off below a strength ratio that halves per level: cautious unless stronger
    /// (1), average when much weaker (0.5), brave when overwhelmingly weaker (0.25).
    public var breaksOff: Bool {
        if confidence >= 4 {
            return false
        }
        if confidence <= 0 {
            return true
        }
        guard strengthRatio.isFinite else { return false }
        return strengthRatio < pow(2, 1 - (confidence + modifier))
    }

    /// The level ratio is clamped to 0.5 through 2 and softened by its square root, so
    /// a level-1 wolf at full health still fights a level-30 player, as in the game.
    public static func strengthRatio(
        level: Int, healthFraction: Float, targetLevel: Int, targetHealthFraction: Float
    ) -> Float {
        let levels = min(max(Float(max(level, 1)) / Float(max(targetLevel, 1)), 0.5), 2)
        let health = max(healthFraction, 0) / max(targetHealthFraction, 0.01)
        return health * levels.squareRoot()
    }

    /// A fixed value per actor, spread over `modifierRange`. Built from the key's own
    /// numbers, because `hashValue` changes between launches.
    public static func modifier(for key: ReferenceKey) -> Float {
        let seed: UInt64 = switch key {
        case let .plugin(name, objectID):
            name.utf8.reduce(UInt64(objectID)) { ($0 &* 31) &+ UInt64($1) }
        case let .generated(number): number
        }
        var hash = seed &* 0x9E37_79B9_7F4A_7C15
        hash ^= hash >> 29
        let unit = Float(hash & 0xFFFF) / Float(UInt16.max)
        return modifierRange
            .lowerBound + unit * (modifierRange.upperBound - modifierRange.lowerBound)
    }
}

/// `Assistance` actor value: whom the actor joins a fight to help.
nonisolated public enum CombatAssistance: Equatable, Sendable {
    case helpsNobody
    case helpsAllies
    case helpsFriendsAndAllies

    public init(value: Float) {
        switch value {
        case ..<0.5: self = .helpsNobody
        case ..<1.5: self = .helpsAllies
        default: self = .helpsFriendsAndAllies
        }
    }

    /// Whether this actor helps one it regards with `reaction`.
    public func helps(_ reaction: ActorReaction) -> Bool {
        switch self {
        case .helpsNobody: false
        case .helpsAllies: reaction == .ally
        case .helpsFriendsAndAllies: reaction == .ally || reaction == .friend
        }
    }
}
