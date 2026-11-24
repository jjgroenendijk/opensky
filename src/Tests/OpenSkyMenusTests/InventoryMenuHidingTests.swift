// A follower's trade list hides its default apparel (UESP "Skyrim:Followers"), a
// vendor's own side lists only what it does not wear, and copies that differ split
// into one row each.

import OpenSkyFormatsESM
import OpenSkyInventoryInterface
@testable import OpenSkyMenus
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

    @Test func aVendorsUnwornSideAddsToItsChest() {
        let worn = InventoryMenuEntry(
            item: FormID(0x10), name: "Cuirass", count: 1, weight: 30, value: 100,
            isEquipped: true, family: nil
        )
        let spare = InventoryMenuEntry(
            item: FormID(0x12), name: "Dagger", count: 2, weight: 2, value: 10,
            isEquipped: false, family: nil, stolenCount: 1
        )
        let own = InventoryMenuModel(
            allEntries: [worn, spare], categories: [], carriedWeight: 34, gold: 50
        )
        let chest = InventoryMenuModel(
            allEntries: [spare], categories: [], carriedWeight: 4, gold: 100
        )
        let merged = chest.adding(own.unworn)
        #expect(merged.allEntries.map(\.item) == [FormID(0x12)])
        #expect(merged.allEntries.first?.count == 4)
        #expect(merged.allEntries.first?.stolenCount == 2)
        #expect(merged.gold == 150)
        let other = InventoryMenuModel(
            allEntries: [worn], categories: [], carriedWeight: 30, gold: 0
        )
        #expect(chest.adding(other).allEntries.map(\.name) == ["Cuirass", "Dagger"])
    }

    @Test func differentCopiesSplitIntoRowsBestFirst() {
        var named = ItemCopy()
        named.name = "Biter"
        let row = InventoryMenuEntry(
            item: FormID(0x12), name: "Dagger", count: 3, weight: 2, value: 10,
            isEquipped: true, family: nil, stolenCount: 1
        )
        let copies = InventoryMenuCopies(value: { _, copy in copy.isPlain ? 10 : 25 })
        let rows = copies.rows(splitting: row, held: [named, .plain, .plain])
        #expect(rows.map(\.name) == ["Biter", "Dagger"])
        #expect(rows.map(\.count) == [1, 2])
        #expect(rows.map(\.value) == [25, 10])
        #expect(rows.map(\.isEquipped) == [true, false])
        #expect(rows.map(\.stolenCount) == [0, 1])
        #expect(rows.first?.copy == named)
        #expect(copies.rows(splitting: row, held: [.plain, .plain]) == [row])
    }
}
