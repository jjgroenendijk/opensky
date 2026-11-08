import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import simd

nonisolated public enum FollowerCommandPhase: Equatable, Sendable {
    case idle
    /// Command mode: the follower waits for a target.
    case choosing(follower: ReferenceKey)
    case walking(follower: ReferenceKey, task: FollowerCommandTask)
    /// The follower stands where the player sent it until the time runs out.
    case waiting(follower: ReferenceKey, left: Float)

    public var follower: ReferenceKey? {
        switch self {
        case .idle: nil
        case let .choosing(follower), let .walking(follower, _), let .waiting(follower, _):
            follower
        }
    }
}

/// What a use-key press on a follower turned out to be.
nonisolated public enum FollowerUseKey: Equatable, Sendable {
    /// Released early: the press activates the follower, which opens the conversation.
    case tap(ReferenceKey)
    /// Held: command mode opens.
    case hold(ReferenceKey)
}

/// How the last command mode or task ended.
nonisolated public enum FollowerCommandOutcome: String, Equatable, Sendable {
    case done, failed, unreachable, cancelled, tooFar, lost
}
