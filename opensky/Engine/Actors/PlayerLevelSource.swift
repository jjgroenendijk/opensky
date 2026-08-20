// The live player level, shared by reference (issue #499, roadmap item 20.6).
//
// ## Why a reference type in a file otherwise made of values
//
// `ActorValueResolver` and `ActorValueBaselineResolver` are immutable values
// built once per load order and read from the cell-build queue. They take the
// player's level as an input, because an NPC flagged `PC Level Mult` scales
// against it (`ActorValueDerivation.level(inputs:playerLevel:)`). Until item
// 20.6 there was no player level to give them, so both defaulted to 1 and every
// scaled actor resolved at the bottom of its range.
//
// A level that changes mid-session cannot be a stored `Int` on those values
// without rebuilding both — and every copy of them a runtime already holds,
// which is several. So the level lives in one small reference the resolvers
// share: raising it moves every derived baseline on the next read, and there is
// no copy left behind reading a stale number. That is the same "re-derive,
// never persist" rule the baselines already follow, extended to their one
// mutable input.
//
// Locked rather than isolated because the readers are `nonisolated` and one of
// them is a build thread; the write is one word from the main actor and the
// read is one word from anywhere.
//
// Documented in docs/engine/character-leveling.md.

import Foundation
import Synchronization

/// The player's character level as every derivation reads it.
nonisolated final class PlayerLevelSource: Sendable {
    /// The level a session with no progression carries: the level the race's
    /// starting attributes are defined for, and the floor every derivation
    /// already clamps to.
    static let startingLevel = 1

    private let stored: Mutex<Int>

    init(_ level: Int = PlayerLevelSource.startingLevel) {
        stored = Mutex(max(Self.startingLevel, level))
    }

    var level: Int {
        stored.withLock { $0 }
    }

    /// Publishes a new level. Anything below the starting level is clamped
    /// rather than refused: a level of zero is not a number this engine has a
    /// derivation for, and the clamp is the same one every consumer applies.
    func set(_ level: Int) {
        stored.withLock { $0 = max(Self.startingLevel, level) }
    }
}
