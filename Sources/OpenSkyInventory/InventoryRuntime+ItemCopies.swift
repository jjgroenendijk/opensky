// Per-copy reads and moves. Copy state lives in its own component; every inventory
// move in `InventoryRuntime` carries the copies it moves. See docs/engine/item-copies.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyWorldState

extension InventoryRuntime {
    public func itemCopies(of holder: InventoryHolder) -> ItemCopyState {
        store.component(ItemCopyState.self, for: holder.key) ?? ItemCopyState()
    }

    /// The quality of the best held copy of `item`, which is the copy an equip wears.
    public func temperLevel(of item: FormID, in holder: InventoryHolder) -> Int32 {
        itemCopies(of: holder).bestLevel(of: item, held: count(of: item, in: holder))
    }

    /// Each held copy of `item`, best first.
    public func copies(of item: FormID, in holder: InventoryHolder) -> [ItemCopy] {
        itemCopies(of: holder).copies(of: item, held: count(of: item, in: holder))
    }

    /// Changes the first held copy of `item` that `matches`. False when none matches.
    @discardableResult
    public func editCopy(
        of item: FormID,
        in holder: InventoryHolder,
        where matches: (ItemCopy) -> Bool,
        _ edit: (inout ItemCopy) -> Void
    ) -> Bool {
        let held = count(of: item, in: holder)
        guard let updated = itemCopies(of: holder).editing(item, held: held, where: matches, edit)
        else { return false }
        writeCopies(updated, for: holder)
        return true
    }

    /// The `count` copies of `item` a move out of `holder` takes: the plainest ones.
    /// Read before the move, because the move changes the held count.
    func leavingCopies(_ count: Int32, of item: FormID, in holder: InventoryHolder) -> [ItemCopy] {
        itemCopies(of: holder).taking(count, of: item, held: self.count(of: item, in: holder))
            .taken
    }

    /// Rewrites `holder`'s copy list after `item` changed from `before` held copies:
    /// `taken` copies left, then `arriving` copies came in.
    func recopy(
        _ item: FormID,
        in holder: InventoryHolder,
        before: Int32,
        taken: Int32 = 0,
        arriving: [ItemCopy] = []
    ) {
        let state = itemCopies(of: holder)
        guard state.copies[item.rawValue] != nil || arriving.contains(where: { !$0.isPlain })
        else { return }
        let remaining = state.taking(taken, of: item, held: before).remaining
        let updated = remaining.giving(arriving, of: item, held: max(0, before - taken))
        writeCopies(updated, for: holder)
    }

    func writeCopies(_ state: ItemCopyState, for holder: InventoryHolder) {
        if state.isEmpty {
            store.reset(ItemCopyState.componentKind, for: holder.key)
        } else {
            store.set(state, for: holder.key, in: holder.cell)
        }
    }
}
