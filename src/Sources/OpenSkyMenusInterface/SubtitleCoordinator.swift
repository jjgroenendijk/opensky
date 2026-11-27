import Foundation

nonisolated public enum SubtitleKind: Sendable {
    /// A line in a conversation the player is in.
    case dialogue
    /// A line spoken near the player outside a conversation, such as a scene.
    case general
}

/// How far the speaker of a line stands, and whether its `INFO` forces a subtitle.
nonisolated public struct SubtitlePlacement: Equatable, Sendable {
    /// `fMaxSubtitleDistance:Interface`. The INI can change it; OpenSky reads no `Skyrim.ini`.
    public static let maximumDistance: Float = 1250
    /// A line with no known distance, such as one in the player's own conversation.
    public static let near = Self(distance: nil, forced: false)

    public var distance: Float?
    public var forced: Bool

    public init(distance: Float?, forced: Bool) {
        self.distance = distance
        self.forced = forced
    }

    /// A line beyond the distance shows no subtitle unless it is forced.
    public var isShown: Bool {
        forced || (distance ?? 0) <= Self.maximumDistance
    }

    /// Forced lines come first; after that, the nearer speaker.
    public func outranks(_ other: Self) -> Bool {
        if forced != other.forced {
            return forced
        }
        return (distance ?? 0) < (other.distance ?? 0)
    }
}

nonisolated public struct SubtitleSettings: Equatable, Sendable {
    public var dialogue: Bool
    public var general: Bool

    public init(dialogue: Bool, general: Bool) {
        self.dialogue = dialogue
        self.general = general
    }

    public func shows(_ kind: SubtitleKind) -> Bool {
        switch kind {
        case .dialogue: dialogue
        case .general: general
        }
    }
}
