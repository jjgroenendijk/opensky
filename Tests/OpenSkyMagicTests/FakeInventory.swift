// A fake `InventoryAccess` for the magic suites: one inventory per key and the
// player's item copies, over the shared value types.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

@MainActor
final class FakeInventory: InventoryAccess {
    let baselines: InventoryBaselineResolver
    let goldFormID = FormID(0x0F)
    private var states: [ReferenceKey: ReferenceInventoryState] = [:]
    private var copyStates: [ReferenceKey: ItemCopyState] = [:]

    init(baselines: InventoryBaselineResolver) {
        self.baselines = baselines
    }

    func inventory(of holder: InventoryHolder) -> ReferenceInventoryState {
        states[holder.key] ?? .empty
    }

    func count(of item: FormID, in holder: InventoryHolder) -> Int32 {
        inventory(of: holder).count(of: item)
    }

    func goldCount(of holder: InventoryHolder) -> Int32 {
        count(of: goldFormID, in: holder)
    }

    @discardableResult
    func add(_ item: FormID, count: Int32, to holder: InventoryHolder) throws
        -> ReferenceInventoryState
    {
        let updated = try inventory(of: holder).adding(item, count: count, owner: holder.key)
        states[holder.key] = updated
        return updated
    }

    @discardableResult
    func remove(_ item: FormID, count: Int32, from holder: InventoryHolder) throws
        -> ReferenceInventoryState
    {
        let before = self.count(of: item, in: holder)
        let updated = try inventory(of: holder).removing(item, count: count, owner: holder.key)
        states[holder.key] = updated
        copyStates[holder.key] = copyState(holder).taking(count, of: item, held: before).remaining
        return updated
    }

    func copies(of item: FormID, in holder: InventoryHolder) -> [ItemCopy] {
        copyState(holder).copies(of: item, held: count(of: item, in: holder))
    }

    @discardableResult
    func editCopy(
        of item: FormID,
        in holder: InventoryHolder,
        where matches: (ItemCopy) -> Bool,
        _ edit: (inout ItemCopy) -> Void
    ) -> Bool {
        let held = count(of: item, in: holder)
        guard let updated = copyState(holder).editing(item, held: held, where: matches, edit)
        else { return false }
        copyStates[holder.key] = updated
        return true
    }

    func confiscateStolen(
        from _: InventoryHolder,
        to _: InventoryHolder
    ) throws -> [InventoryStack] {
        []
    }

    private func copyState(_ holder: InventoryHolder) -> ItemCopyState {
        copyStates[holder.key] ?? ItemCopyState()
    }
}
