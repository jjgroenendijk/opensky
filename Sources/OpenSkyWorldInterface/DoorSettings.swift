// How near the player must be for an automatic door to open or show its name, and how
// long a teleport door waits before the load, from the `fAutoDoor*` and
// `fTeleportDoorActivateDelayTimer` settings (docs/engine/interaction.md#automatic-doors).

import OpenSkyGameData

nonisolated public struct DoorSettings: Equatable, Sendable {
    /// `fAutoDoorActivateDistance`: the feet must be this near the door reference too.
    public var autoActivateDistance: Float = 350
    /// `fAutoDoorDisplayDistance`: an automatic door this near names itself on the HUD.
    public var autoDisplayDistance: Float = 700
    /// `fTeleportDoorActivateDelayTimer`: seconds between using a load door and the load.
    public var teleportDelay: Float = 0.6

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
