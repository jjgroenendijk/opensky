public import OpenSkyFormatsCore
public import OpenSkyGameData

/// What the world adapters use of `PlayerSettingsCoordinator`.
public protocol PlayerSettingsPort: AnyObject {
    func applyAll()
    func buttonName(forUserEvent event: String) -> String?
    func loadControlMap(_ file: ControlMapFile?)
    var store: PlayerSettingsStore { get }
}
