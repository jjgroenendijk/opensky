import OpenSkyFormatsESM
public import OpenSkyWorldState

nonisolated public enum LockActionOutcome: Equatable, Sendable {
    case idle
    case noRuntime
    case noSelection
    case noLock(name: String)
    case blockedByPerk(name: String)
    case unlockedWithKey(name: String)
    case refused(name: String, difficulty: LockDifficulty)
    case lockChanged(name: String, locked: Bool)
    case picking(name: String, difficulty: LockDifficulty)
    case pickRefused(LockpickingRefusal, name: String)
    case notice(LockNotice)
    case pickBroke
    case stoppedPicking
    case picked(name: String?)
    /// Someone saw an owned lock picked.
    case caughtPicking(bounty: Int32)
}

/// A refused press that opens no minigame. The HUD shows the game's own text.
nonisolated public enum LockNotice: Equatable, Sendable {
    case requiresKey
    case outOfLockpicks
    /// Guards chase the player.
    case pursued
}
