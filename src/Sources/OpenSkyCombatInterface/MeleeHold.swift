import Foundation

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
