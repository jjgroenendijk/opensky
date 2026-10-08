// Per-copy quality reads. Quality lives in its own component; see
// `TemperedItemState` for why a take or drop leaves it alone.

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
}
