public import OpenSkyFormatsESM
public import OpenSkyInventory
public import OpenSkyInventoryInterface
public import OpenSkySessionInterface

extension EquipmentRuntime: EquipmentRuntimePort {}
extension InventoryCoordinator: InventoryPort {
    @discardableResult public func pickpocket(
        _ stack: (item: FormID, count: Int32),
        named name: String,
        from target: InventoryHolder,
        roll: Float
    ) -> PickpocketOutcome {
        pickpocket(stack.item, count: stack.count, named: name, from: target, roll: roll)
    }

    @discardableResult public func plant(
        _ stack: (item: FormID, count: Int32),
        named name: String,
        into target: InventoryHolder,
        roll: Float
    ) -> PickpocketOutcome {
        plant(stack.item, count: stack.count, named: name, into: target, roll: roll)
    }
}

extension InventoryRuntime: InventoryRuntimePort {
    public func transfer(
        _ item: FormID,
        count: Int32,
        from source: InventoryHolder,
        to destination: InventoryHolder
    ) throws {
        try transfer(item, count: count, from: source, to: destination, markingStolen: false)
    }
}

extension LockCoordinator: LockPort {}
extension VendorCoordinator: VendorPort {}
extension VendorCore: VendorCorePort {}
extension WorldItemRuntime: WorldItemRuntimePort {}
