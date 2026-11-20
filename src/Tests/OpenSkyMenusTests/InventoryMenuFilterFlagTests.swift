// The tab bits of the vanilla item movies: a tab with flag 0 draws as a divider, and
// a row with no filter flag passes the movie's tab filter.

import OpenSkyFormatsESM
import OpenSkyFormatsSWF
@testable import OpenSkyGameData
@testable import OpenSkyMenus
import Testing

struct InventoryMenuFilterFlagTests {
    private let tabs = InventoryMenuCategory.tabs(texts: .vanilla, favourites: true)

    private func entry(_ item: UInt32) -> InventoryMenuEntry {
        InventoryMenuEntry(
            item: FormID(item), name: "\(item)", count: 1, weight: 0, value: 0,
            isEquipped: false, family: .weapon
        )
    }

    @Test func everyTabHasItsOwnBitAndNoneIsADivider() {
        let model = InventoryMenuModel(allEntries: [], categories: tabs, carriedWeight: 0, gold: 0)
        let flags = InventoryMenuMovieBridge.categoryRows(model).map { $0["flag"] }
        #expect(flags.count == tabs.count)
        #expect(Set(flags.map { $0.map(String.init(describing:)) }).count == tabs.count)
        #expect(!flags.contains(.integer(0)))
        #expect(InventoryMenuMovieBridge.categoryRows(model).allSatisfy {
            $0["bDontHide"] == .boolean(true)
        })
    }

    @Test func aRowHasNoFilterFlagSoTheMovieKeepsIt() {
        let row = InventoryMenuMovieBridge.row(for: entry(1), index: 0)
        #expect(row["filterFlag"] == nil)
    }
}
