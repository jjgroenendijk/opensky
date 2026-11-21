import OpenSkyFormatsCore
public import OpenSkyGameData
public import OpenSkyMenusInterface

/// What the world adapters use of `PlayerSettingsCoordinator`.
public protocol PlayerSettingsPort: AnyObject {
    func buttonName(forUserEvent event: String) -> String?
    var store: PlayerSettingsStore { get }
    func keyName(_ scanCode: UInt32) -> String
    /// A scan code as hex ("0x39") or decimal, or a key by its shown name ("Space").
    func scanCode(named name: String) -> UInt32?
    func action(forScanCode scanCode: UInt32, inMenu: Bool) -> GameInputAction?
}
