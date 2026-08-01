// The two-pane container/barter list (issue #179): which side the item list is
// showing, what activating a row would do, per-side pricing, and the selection
// restore every transaction depends on. Synthetic fixtures only.

import Foundation
@testable import opensky
import Testing

struct ContainerMenuModelTests {
    private func entry(
        _ name: String,
        item: UInt32,
        value: Int32,
        count: Int32 = 1
    ) -> InventoryMenuEntry {
        InventoryMenuEntry(
            item: FormID(item), name: name, count: count, weight: 1, value: value,
            isEquipped: false, family: .miscellaneous
        )
    }

    private func list(_ entries: [InventoryMenuEntry], gold: Int32) -> InventoryMenuModel {
        InventoryMenuModel(
            allEntries: entries,
            categories: InventoryMenuCategory.engineOrder,
            carriedWeight: 0,
            gold: gold
        )
    }

    private func model(mode: ContainerMenuModel.Mode) -> ContainerMenuModel {
        ContainerMenuModel(
            mode: mode,
            container: list(
                [
                    entry("Cuirass", item: 0x300, value: 125),
                    entry("Helmet", item: 0x400, value: 60)
                ],
                gold: 500
            ),
            player: list([entry("Sword", item: 0x200, value: 25, count: 2)], gold: 1000),
            pricing: .vanilla,
            containerName: "Test Chest"
        )
    }

    @Test func theActiveSideIsTheContainerFirst() {
        let model = model(mode: .container)
        #expect(model.side == .container)
        #expect(model.active.entries.map(\.name) == ["Cuirass", "Helmet"])
        #expect(model.transferLabel == "Take")
    }

    @Test func switchingSidesShowsTheOtherOwnerAndResetsTheRow() {
        var model = model(mode: .container)
        model.moveSelection(by: 1)
        #expect(model.selectedEntry?.name == "Helmet")

        model.switchSide()
        #expect(model.side == .player)
        #expect(model.active.entries.map(\.name) == ["Sword"])
        #expect(model.selectedEntry?.name == "Sword")
        #expect(model.transferLabel == "Store")

        model.switchSide()
        #expect(model.selectedEntry?.name == "Cuirass", "the other side starts at the top again")
    }

    @Test func barterLabelsAreBuyAndSell() {
        var model = model(mode: .barter)
        #expect(model.transferLabel == "Buy")
        model.switchSide()
        #expect(model.transferLabel == "Sell")
    }

    /// The merchant's stock is priced at the buy price and the player's at the
    /// sell price, which is what makes the same row show two numbers depending
    /// on which side of the counter it is on.
    @Test func pricesFollowTheSideTheRowIsOn() throws {
        var model = model(mode: .barter)
        let stock = try #require(model.selectedEntry)
        #expect(model.price(for: stock) == 388)

        model.switchSide()
        let carried = try #require(model.selectedEntry)
        #expect(model.price(for: carried) == 8)
    }

    @Test func containerModePricesNothing() throws {
        let model = model(mode: .container)
        #expect(try model.price(for: #require(model.selectedEntry)) == nil)
        #expect(model.canAffordSelection, "a free transfer is always affordable")
    }

    /// The paying side is the player when buying and the merchant when selling,
    /// so a rich player and a broke merchant disagree about the same row.
    @Test func affordabilityAsksThePayingSide() {
        var model = ContainerMenuModel(
            mode: .barter,
            container: list([entry("Cuirass", item: 0x300, value: 125)], gold: 0),
            player: list([entry("Sword", item: 0x200, value: 25)], gold: 10),
            pricing: .vanilla,
            containerName: "Broke Chest"
        )
        #expect(!model.canAffordSelection, "the player has 10 gold and the cuirass costs 388")

        model.switchSide()
        #expect(!model.canAffordSelection, "the merchant has no gold to buy the sword with")
    }

    /// Every transaction rebuilds both panes, and the selection has to survive
    /// that or the cursor jumps to the top after each transfer.
    @Test func restoreCarriesTheSideAndBothSelections() {
        var before = model(mode: .barter)
        before.moveSelection(by: 1)
        before.switchSide()

        var rebuilt = model(mode: .barter)
        rebuilt.restore(from: before)

        #expect(rebuilt.side == .player)
        #expect(rebuilt.container.selectedIndex == 1, "the container's own row survived")
        #expect(rebuilt.selectedEntry?.name == "Sword")
    }

    /// The row that just moved out no longer exists; the restore drops that
    /// index rather than pointing at whatever took its place.
    @Test func restoreDropsASelectionThatNoLongerExists() {
        var before = model(mode: .container)
        before.moveSelection(by: 1)

        var emptied = ContainerMenuModel(
            mode: .container,
            container: list([entry("Cuirass", item: 0x300, value: 125)], gold: 500),
            player: list([], gold: 1000),
            pricing: .vanilla,
            containerName: "Test Chest"
        )
        emptied.restore(from: before)
        #expect(emptied.container.selectedIndex == 0)
    }

    @Test func theTwoPursesAreTheTwoOwnersGoldStacks() {
        let model = model(mode: .barter)
        #expect(model.containerGold == 500)
        #expect(model.playerGold == 1000)
    }

    @Test func anEmptyModelIsUsableWithNoContainerAtAll() {
        let model = ContainerMenuModel.empty
        #expect(model.selectedEntry == nil)
        #expect(model.transferLabel == "Take")
        #expect(model.containerName == "none")
    }
}
