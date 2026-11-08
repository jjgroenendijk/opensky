public import OpenSkyGameData

/// `fFavorRequest*` settings. The CK wiki lists them without a use, so each use is
/// OpenSky's reading (docs/engine/follower-commands.md).
nonisolated public struct FollowerCommandSettings: Equatable, Sendable {
    /// How far from the player's eye a command target may be.
    public var pickDistance: Float = 2100
    /// Command mode ends when the follower is farther than this from the player.
    public var radius: Float = 4000
    /// Seconds the follower waits at a spot the player sent it to.
    public var waitSeconds: Float = 40
    /// How close the follower walks to its target before it acts.
    public var reach: Float = 128
    /// How long the use key stays down on a follower before it opens command mode.
    public var holdSeconds: Float = 0.5

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fFavorRequestPickDistance", into: &settings, \.pickDistance)
        store.read("fFavorRequestRadius", into: &settings, \.radius)
        store.read("fFavorRequestWaitTimer", into: &settings, \.waitSeconds)
        return settings
    }
}
