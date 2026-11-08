public import OpenSkyProgressionInterface

/// What the world adapters use of `PlayerLevelRuntime`.
public protocol PlayerLevelRuntimePort {
    var experienceForNextLevel: Float { get }
    var level: Int { get }
    var state: PlayerProgressState { get }
}
