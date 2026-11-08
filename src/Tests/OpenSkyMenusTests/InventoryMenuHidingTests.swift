// A follower's trade list hides its default apparel (UESP "Skyrim:Followers").

import OpenSkyFormatsESM
import OpenSkyMenus
import Testing

struct InventoryMenuHidingTests {
    @Test func theTradeListHidesTheOutfitCopies() {
        let cuirass = InventoryMenuEntry(
            item: FormID(0x10), name: "Cuirass", count: 2, weight: 30, value: 100,
            isEquipped: true, family: nil
        )
        let boots = InventoryMenuEntry(
            item: FormID(0x11), name: "Boots", count: 1, weight: 5, value: 10,
            isEquipped: true, family: nil
        )
        let model = InventoryMenuModel(
            allEntries: [boots, cuirass], categories: [], carriedWeight: 65, gold: 0
        )
        let hidden = model.hiding([FormID(0x10): 1, FormID(0x11): 1])
        #expect(hidden.allEntries.map(\.item) == [FormID(0x10)])
        #expect(hidden.allEntries.first?.count == 1)
        #expect(hidden.allEntries.first?.isEquipped == false)
    }
}
