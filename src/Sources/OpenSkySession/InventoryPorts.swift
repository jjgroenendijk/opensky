public import OpenSkyFormatsESM
public import OpenSkyInventory
public import OpenSkyInventoryInterface
public import OpenSkySessionInterface

extension EquipmentRuntime: EquipmentRuntimePort {}
extension InventoryCoordinator.AlchemyLab: InventoryAlchemyLabPort {}
extension InventoryCoordinator.ArmourWeights: InventoryArmourWeightsPort {}
extension InventoryCoordinator.Consumables: InventoryConsumablesPort {}
extension InventoryCoordinator.ContainerTrade: InventoryContainerTradePort {}
extension InventoryCoordinator.CraftingBench: InventoryCraftingBenchPort {}
extension InventoryCoordinator.CraftingReadout: InventoryCraftingReadoutPort {}
extension InventoryCoordinator.DeathItems: InventoryDeathItemsPort {}
extension InventoryCoordinator.EquipmentChanges: InventoryEquipmentChangesPort {}
extension InventoryCoordinator.FavouriteItems: InventoryFavouriteItemsPort {}
extension InventoryCoordinator.FollowerTakes: InventoryFollowerTakesPort {}
extension InventoryCoordinator.ItemActions: InventoryItemActionsPort {}
extension InventoryCoordinator.ItemCards: InventoryItemCardsPort {}
extension InventoryCoordinator.ItemConditions: InventoryItemConditionsPort {}
extension InventoryCoordinator.ItemPanels: InventoryItemPanelsPort {}
extension InventoryCoordinator.Pickpocketing: InventoryPickpocketingPort {
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

extension InventoryCoordinator.ReadoutLines: InventoryReadoutLinesPort {}
extension InventoryCoordinator.ScriptItems: InventoryScriptItemsPort {}
extension InventoryCoordinator.TeammateTrades: InventoryTeammateTradesPort {}
extension InventoryCoordinator: InventoryPort {}

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
