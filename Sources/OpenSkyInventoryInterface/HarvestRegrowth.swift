// When a harvested plant grows back: when its cell resets, after the load order's
// `iHoursToRespawnCell` game hours (240 in Skyrim.esm). OpenSky counts from the
// harvest, not from the player's last visit. See docs/engine/interaction.md.

import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public struct HarvestRegrowth: Equatable, Sendable {
    public static let settingName = "iHoursToRespawnCell"
    /// `iHoursToRespawnCell` in Skyrim.esm, read from the install.
    public static let vanillaHours: Float = 240
    public static let vanilla = HarvestRegrowth(hours: vanillaHours)

    /// Game hours from a harvest to the regrowth. Never zero or negative.
    public let hours: Float

    /// A non-finite or non-positive value falls back to the vanilla hours.
    public init(hours: Float) {
        self.hours = hours.isFinite && hours > 0 ? hours : Self.vanillaHours
    }

    /// The game day `state`'s plant grows back on. Nil when it is not harvested,
    /// or when the harvest time is unknown, which never regrows on its own.
    public func regrowthDay(of state: ReferenceHarvestState?) -> Float? {
        guard let state, state.isHarvested, let day = state.harvestedOnDay else { return nil }
        return day + hours / 24
    }

    /// Whether the plant still reads as harvested on game day `day`. Without a
    /// clock, a harvested plant stays harvested.
    public func isHarvested(_ state: ReferenceHarvestState?, onDay day: Float?) -> Bool {
        guard let state, state.isHarvested else { return false }
        guard let day, let regrowth = regrowthDay(of: state) else { return true }
        return day < regrowth
    }

    public static func resolve(store: GameSettingStore) -> HarvestRegrowth {
        guard
            let resolved = store.setting(editorID: settingName),
            case let .integer(value) = resolved.setting.value
        else { return .vanilla }
        return HarvestRegrowth(hours: Float(value))
    }
}
