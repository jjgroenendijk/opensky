import OpenSkyFormatsCore
public import OpenSkyGameData

/// What the world adapters use of `PlayerSettingsCoordinator`.
public protocol PlayerSettingsPort: AnyObject {
    func buttonName(forUserEvent event: String) -> String?
    var store: PlayerSettingsStore { get }
}
