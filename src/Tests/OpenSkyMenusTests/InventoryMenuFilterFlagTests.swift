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

    /// `equipState` takes the `ES_` values of `InventoryDefines`, and `favorite` the
    /// player's mark.
    @Test func aRowSendsItsEquipStateAndFavourite() {
        let weapon = InventoryMenuEntry(
            item: FormID(7), name: "Sword", count: 2, weight: 9, value: 25,
            isEquipped: true, family: .weapon, isFavourite: true
        )
        let built = InventoryMenuModel.heldHands
        #expect(built(weapon, nil) == .rightHand)
        #expect(built(weapon, LeftHandHold(item: FormID(7))) == .leftHand)
        #expect(built(weapon, LeftHandHold(item: FormID(7), paired: true)) == .bothHands)
        var held = weapon
        held.hands = .leftHand
        let row = InventoryMenuMovieBridge.row(for: held, index: 0)
        #expect(row["equipState"] == .integer(InventoryEquipState.leftHand.rawValue))
        #expect(row["favorite"] == .boolean(true))
        let armour = InventoryMenuEntry(
            item: FormID(8), name: "Helmet", count: 1, weight: 2, value: 10,
            isEquipped: true, family: .armor
        )
        #expect(built(armour, nil).isEmpty)
        #expect(
            InventoryMenuMovieBridge.row(for: armour, index: 1)["equipState"]
                == .integer(InventoryEquipState.equipped.rawValue)
        )
        #expect(
            InventoryMenuMovieBridge.row(for: entry(1), index: 2)["equipState"]
                == .integer(InventoryEquipState.none.rawValue)
        )
        #expect(InventoryEquipState(isEquipped: true, hands: .bothHands) == .bothHands)
        #expect(InventoryEquipState(isEquipped: true, hands: .rightHand).rawValue == 3)
    }
}
