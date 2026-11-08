// The live player level, shared by reference. The resolvers are immutable values
// read on the build queue, and `PC Level Mult` actors scale against this level. A
// reference lets a level-up move every derived baseline without rebuilding copies.
// Locked, not isolated, because a build thread reads it.
// See docs/engine/character-leveling.md.

import Foundation
import Synchronization

/// The player's character level as every derivation reads it.
nonisolated public final class PlayerLevelSource: Sendable {
    /// The level a session with no progression carries: the level the race's
    /// starting attributes are defined for, and the floor every derivation
    /// already clamps to.
    public static let startingLevel = 1

    private let stored: Mutex<Int>

    public init(_ level: Int = PlayerLevelSource.startingLevel) {
        stored = Mutex(max(Self.startingLevel, level))
    }

    public var level: Int {
        stored.withLock { $0 }
    }

    /// Publishes a new level. Anything below the starting level is clamped
    /// rather than refused: a level of zero is not a number this engine has a
    /// derivation for, and the clamp is the same one every consumer applies.
    public func set(_ level: Int) {
        stored.withLock { $0 = max(Self.startingLevel, level) }
    }
}
