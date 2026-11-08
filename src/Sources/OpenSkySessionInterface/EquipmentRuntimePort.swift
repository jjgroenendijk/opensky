public import OpenSkyFormatsESM
public import OpenSkyInventoryInterface

/// What the world adapters use of `EquipmentRuntime`.
public protocol EquipmentRuntimePort: EquipmentAccess {
    associatedtype InventoryRuntime: InventoryRuntimePort
    func equipped(on holder: InventoryHolder) -> [FormID]
    var inventory: InventoryRuntime { get }
}
