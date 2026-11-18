import Foundation

/// Which hand the swing in progress strikes with.
nonisolated public enum MeleeStrikeHand: String, Equatable, Sendable {
    case right
    case left
    /// Both weapons at once, from both buttons pressed together.
    case dual
}

/// What the swing in progress is.
nonisolated public enum MeleeStrikeKind: String, Equatable, Sendable {
    case normal
    case power
    case bash
    case powerBash

    public var isPowerAttack: Bool {
        self == .power || self == .powerBash
    }

    public var isBash: Bool {
        self == .bash || self == .powerBash
    }
}
