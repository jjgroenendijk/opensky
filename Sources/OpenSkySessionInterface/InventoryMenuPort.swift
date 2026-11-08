public import OpenSkyMenusInterface

/// What the world adapters use of `InventoryMenuController`.
public protocol InventoryMenuPort: AnyObject {
    func tick(now: Double)
    func open()
    var snapshot: InventoryMenuControlSnapshot { get }
    func useHotkey(_ slot: Int)
    func route(_ event: MenuInputEvent)
}
