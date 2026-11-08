import Foundation
import OpenSkyConditions
public import OpenSkyFormatsESM
import OpenSkyProgressionInterface
import OpenSkyWorldInterface
public import OpenSkyWorldState

/// A reference's lock as stored, and the level it shows now.
nonisolated public struct ResolvedLock: Sendable {
    public let key: ReferenceKey
    public let state: ReferenceLockState
    /// Differs from `state.level` only on a leveled lock the player has outgrown.
    public let shownLevel: UInt8
    public let isLeveled: Bool

    /// `state` with the shown level, for every rule that picks a band.
    public var shown: ReferenceLockState {
        var shown = state
        shown.level = shownLevel
        return shown
    }

    public init(
        key: ReferenceKey,
        state: ReferenceLockState,
        shownLevel: UInt8,
        isLeveled: Bool
    ) {
        self.key = key
        self.state = state
        self.shownLevel = shownLevel
        self.isLeveled = isLeveled
    }
}

/// Why a lockpicking session did not start.
nonisolated public enum LockpickingRefusal: Error, Equatable, Sendable {
    case noRuntime
    case unknownReference(FormID)
    case notLocked
    case requiresKey
    case noLockpicks
}

/// How the last lockpicking session ended.
nonisolated public struct LockpickingOutcome: Equatable, Sendable {
    public let difficulty: LockDifficulty
    public let opened: Bool
    public let picksBroken: Int
    public let experience: Float
    public let keyRewarded: Bool

    public init(
        difficulty: LockDifficulty,
        opened: Bool,
        picksBroken: Int,
        experience: Float,
        keyRewarded: Bool
    ) {
        self.difficulty = difficulty
        self.opened = opened
        self.picksBroken = picksBroken
        self.experience = experience
        self.keyRewarded = keyRewarded
    }
}
