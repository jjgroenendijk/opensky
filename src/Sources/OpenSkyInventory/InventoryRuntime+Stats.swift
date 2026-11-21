// The gold and trade stats on the journal's Stats page. See docs/engine/statistics.md.

import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyQuestsInterface
import OpenSkyWorldState

extension InventoryRuntime {
    /// Gold the player picks up, from the world, a chest, or a body, counts as found.
    func countPickUp(of item: FormID, count: Int32, by holder: InventoryHolder) {
        guard item == goldFormID, holder.key == .player else { return }
        let gold = self.count(of: goldFormID, in: .player)
        store.updateMiscStats {
            $0.increment("Gold Found", by: count)
            $0.raise("Most Gold Carried", to: gold)
        }
    }

    /// One buy or one sell with a merchant.
    func countBarter() {
        let gold = count(of: goldFormID, in: .player)
        store.updateMiscStats {
            $0.increment("Barters")
            $0.raise("Most Gold Carried", to: gold)
        }
    }
}
