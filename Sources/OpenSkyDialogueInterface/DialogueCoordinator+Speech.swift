import OpenSkyConditions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM

/// One NPC as the ambient speech pass sees it.
nonisolated public struct AmbientSpeaker: Equatable, Sendable {
    public let key: ReferenceKey
    public let distanceToPlayer: Float
    /// Whether it detects the player.
    public let seesPlayer: Bool
    /// Engaged in a fight.
    public let isFighting: Bool
    /// Alive, not in a scene, and not in the player's conversation.
    public let isFree: Bool
    /// Its package allows hellos to the player (`PKDT` interrupt flag 0x01).
    public let allowsHello: Bool

    public init(
        key: ReferenceKey, distanceToPlayer: Float, seesPlayer: Bool, isFighting: Bool,
        isFree: Bool, allowsHello: Bool
    ) {
        self.key = key
        self.distanceToPlayer = distanceToPlayer
        self.seesPlayer = seesPlayer
        self.isFighting = isFighting
        self.isFree = isFree
        self.allowsHello = allowsHello
    }
}

/// The loaded NPCs for one ambient speech pass.
nonisolated public struct AmbientSpeechFrame: Equatable, Sendable {
    /// OpenSky's: no setting names how near an idle comment must be to be said.
    public static let idleChatterDistance: Float = 1000

    public let speakers: [AmbientSpeaker]
    public let now: Double
    public let playerInConversation: Bool

    public init(speakers: [AmbientSpeaker], now: Double, playerInConversation: Bool) {
        self.speakers = speakers
        self.now = now
        self.playerInConversation = playerInConversation
    }
}

/// A line the ambient speech pass chose.
nonisolated public struct AmbientLine: Equatable, Sendable {
    public let info: FormID
    public let speaker: ReferenceKey
    public let kind: NPCSpeechLine

    public init(info: FormID, speaker: ReferenceKey, kind: NPCSpeechLine) {
        self.info = info
        self.speaker = speaker
        self.kind = kind
    }
}
