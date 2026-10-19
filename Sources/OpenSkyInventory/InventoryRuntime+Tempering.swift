// Per-copy quality reads and moves. Quality lives in its own component; every
// inventory move in `InventoryRuntime` carries the levels of the copies it moves.

import Foundation
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyWorldState

extension InventoryRuntime {
    public func temperedItems(of holder: InventoryHolder) -> TemperedItemState {
        store.component(TemperedItemState.self, for: holder.key) ?? TemperedItemState()
    }

    /// The quality of the best held copy of `item`, which is the copy an equip wears.
    public func temperLevel(of item: FormID, in holder: InventoryHolder) -> Int32 {
        temperedItems(of: holder).bestLevel(of: item, held: count(of: item, in: holder))
    }

    /// The levels of the `count` copies of `item` a move out of `holder` takes: the
    /// lowest ones. Read before the move, because the move changes the held count.
    func leavingLevels(_ count: Int32, of item: FormID, in holder: InventoryHolder) -> [Int32] {
        temperedItems(of: holder).taking(count, of: item, held: self.count(of: item, in: holder))
            .taken
    }

    /// Rewrites `holder`'s quality list after `item` changed from `before` held copies:
    /// `taken` copies left, then copies at `arriving` levels came in.
    func retemper(
        _ item: FormID,
        in holder: InventoryHolder,
        before: Int32,
        taken: Int32 = 0,
        arriving: [Int32] = []
    ) {
        let state = temperedItems(of: holder)
        guard state.levels[item.rawValue] != nil || arriving.contains(where: { $0 > 0 }) else {
            return
        }
        let remaining = state.taking(taken, of: item, held: before).remaining
        let updated = remaining.giving(arriving, of: item, held: max(0, before - taken))
        writeTempered(updated, for: holder)
    }

    func writeTempered(_ state: TemperedItemState, for holder: InventoryHolder) {
        if state.isEmpty {
            store.reset(TemperedItemState.componentKind, for: holder.key)
        } else {
            store.set(state, for: holder.key, in: holder.cell)
        }
    }
}
