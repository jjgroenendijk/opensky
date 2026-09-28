// The seam other features reach an inventory through. `InventoryRuntime` conforms,
// and the composition root hands it over as this protocol.

import OpenSkyFormatsESM

/// Gold and stolen goods in one holder's inventory, over the world-state store.
@MainActor
public protocol InventoryAccess {
    /// The gold item, `Gold001` in vanilla.
    var goldFormID: FormID { get }

    /// How much gold `holder` carries.
    func goldCount(of holder: InventoryHolder) -> Int32

    /// Takes `count` of `item` out of `holder`.
    ///
    /// - Throws: `InventoryError` when `holder` has fewer, which writes nothing.
    @discardableResult
    func remove(_ item: FormID, count: Int32, from holder: InventoryHolder) throws
        -> ReferenceInventoryState

    /// Moves every stolen stack from `source` to `destination`.
    func confiscateStolen(
        from source: InventoryHolder,
        to destination: InventoryHolder
    ) throws -> [InventoryStack]
}
