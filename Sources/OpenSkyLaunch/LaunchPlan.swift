// What Play does, from the launch options: load the newest save, open the main
// menu, or start a new game at the chosen start.

import Foundation
import OpenSkyGameData

nonisolated public enum LaunchPlan: Equatable, Sendable {
    /// Loads the save in this slot, past the main menu.
    case resume(slot: String)
    /// Opens the main menu, where Continue is the first row when a save exists.
    case mainMenu
    /// Starts a new game at a cell or a grid cell.
    case newGame(LaunchStart)

    /// Without a save, Resume falls back to the new game start.
    public init(
        resumesLatestSave: Bool, skipsMainMenu: Bool, newestSlot: String?, start: LaunchStart
    ) {
        if resumesLatestSave, let newestSlot {
            self = skipsMainMenu ? .resume(slot: newestSlot) : .mainMenu
        } else {
            self = start == .normal ? .mainMenu : .newGame(start)
        }
    }

    /// The start the Play window opens with.
    public var start: LaunchStart {
        if case let .newGame(start) = self {
            return start
        }
        return .normal
    }
}

nonisolated extension LaunchPreferences {
    public static let resumesLatestSaveSetting = SettingKey(
        "OpenSkyLaunchResumesLatestSave", default: false
    )
    public static let skipsMainMenuSetting = SettingKey(
        "OpenSkyLaunchSkipsMainMenu", default: true
    )
}
