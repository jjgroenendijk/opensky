public import OpenSkyProgressionInterface

/// What the world adapters use of `PlayerLevelRuntime`.
public protocol PlayerLevelRuntimePort {
    var experienceForNextLevel: Float { get }
    var level: Int { get }
    /// Levels the banked experience has earned and the skills menu has not applied.
    var levelsReady: Int { get }
    var state: PlayerProgressState { get }
}
