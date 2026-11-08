import Foundation

nonisolated public enum SubtitleKind: Sendable {
    /// A line in a conversation the player is in.
    case dialogue
    /// A line spoken near the player outside a conversation, such as a scene.
    case general
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
