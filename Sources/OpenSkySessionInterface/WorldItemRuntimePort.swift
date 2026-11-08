public import OpenSkyInventoryInterface
public import OpenSkyWorldInterface

/// What the world adapters use of `WorldItemRuntime`.
public protocol WorldItemRuntimePort: AnyObject, Sendable {
    associatedtype InventoryRuntime: InventoryRuntimePort
    var inventory: InventoryRuntime { get }
    func isTheft(_ interaction: PlacedInteraction) -> Bool
    var player: InventoryHolder { get }
}
