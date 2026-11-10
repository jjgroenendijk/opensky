public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
public import OpenSkyWorldState

/// What the world adapters use of `InventoryRuntime`.
public protocol InventoryRuntimePort: InventoryAccess, Sendable {
    @discardableResult func add(
        _ item: FormID,
        count: Int32,
        to holder: InventoryHolder
    ) throws -> ReferenceInventoryState
    var baselines: InventoryBaselineResolver { get }
    func count(of item: FormID, in holder: InventoryHolder) -> Int32
    func goldCount(of holder: InventoryHolder) -> Int32
    var goldFormID: FormID { get }
    func hasRuntimeInventory(_ holder: InventoryHolder) -> Bool
    func inventory(of holder: InventoryHolder) -> ReferenceInventoryState
    @discardableResult func remove(
        _ item: FormID,
        count: Int32,
        from holder: InventoryHolder
    ) throws -> ReferenceInventoryState
    func roll(of holder: InventoryHolder) -> LeveledRoll
    var store: WorldStateStore { get }
    func temperLevel(of item: FormID, in holder: InventoryHolder) -> Int32
    func transfer(
        _ item: FormID,
        count: Int32,
        from source: InventoryHolder,
        to destination: InventoryHolder
    ) throws
}
