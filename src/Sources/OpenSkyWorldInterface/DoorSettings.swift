// How near the player must be for an automatic door to open or show its name, and how
// long a teleport door waits before the load, from the `fAutoDoor*` and
// `fTeleportDoorActivateDelayTimer` settings (docs/engine/interaction.md#automatic-doors).

public import OpenSkyGameData

nonisolated public struct DoorSettings: Equatable, Sendable {
    /// `fAutoDoorActivateDistance`: the feet must be this near the door reference too.
    public var autoActivateDistance: Float = 350
    /// `fAutoDoorDisplayDistance`: an automatic door this near names itself on the HUD.
    public var autoDisplayDistance: Float = 700
    /// `fTeleportDoorActivateDelayTimer`: seconds between using a load door and the load.
    public var teleportDelay: Float = 0.6
    /// The fade to black when the player uses a door with the use key, or walks into one.
    public var normalFade = DoorFade.normalDoor
    public var automaticFade = DoorFade.automaticDoor

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fAutoDoorActivateDistance", into: &settings, \.autoActivateDistance)
        store.read("fAutoDoorDisplayDistance", into: &settings, \.autoDisplayDistance)
        store.read("fTeleportDoorActivateDelayTimer", into: &settings, \.teleportDelay)
        return settings
    }
}

/// How the view darkens before a door's load: it holds for `wait` seconds, then turns
/// black over `seconds` (docs/engine/loading-screens.md#timeline).
nonisolated public struct DoorFade: Equatable, Sendable {
    public var wait: Double
    public var seconds: Double

    /// A teleport that is not the player using a door: the view goes dark at once.
    public static let none = Self(wait: 0, seconds: 0)
    public static let normalDoor = Self(wait: 0.01, seconds: 0.4)
    public static let automaticDoor = Self(wait: 0, seconds: 0.5)

    public var total: Double {
        wait + seconds
    }
}
