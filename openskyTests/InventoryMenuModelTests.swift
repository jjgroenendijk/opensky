// InventoryMenuModel unit tests (issue #289): the row list the inventory menu
// presents — naming, sorting, per-row and total arithmetic, the gold split,
// category filtering, and the navigation rules.
//
// Device-free and movie-free. The rows come from `InventoryBaselineFixture`'s
// synthetic plugin, so nothing here reads a real game file.

import Foundation
@testable import opensky
import Testing

@MainActor
struct InventoryMenuModelTests {
    private typealias Fixture = InventoryBaselineFixture

    private func items() throws -> ItemDefinitionStore {
        try InventoryBaselineFixture.resolver().items
    }

    /// One of each family the fixture defines, plus gold and a form the plugin
    /// never describes.
    private func mixedInventory() -> ReferenceInventoryState {
        ReferenceInventoryState(
            stacks: [
                InventoryStack(item: Fixture.gold, count: 42),
                InventoryStack(item: Fixture.lockpick, count: 3),
                InventoryStack(item: Fixture.sword, count: 1),
                InventoryStack(item: Fixture.cuirass, count: 2),
                InventoryStack(item: FormID(0x00FF_FFFF), count: 1)
            ],
            equipped: [Fixture.sword]
        )
    }

    private func model() throws -> InventoryMenuModel {
        try InventoryMenuModel.build(inventory: mixedInventory(), items: items())
    }

    // MARK: - Rows

    /// Gold is an ordinary MISC stack in the store, so the model has to take it
    /// out of the rows deliberately or the player sees a "Gold001" line.
    @Test func goldBecomesAReadoutRatherThanARow() throws {
        let model = try model()
        #expect(model.gold == 42)
        #expect(model.allEntries.contains { $0.item == Fixture.gold } == false)
    }

    @Test func rowsCarryCountWeightValueAndEquippedFlag() throws {
        let model = try model()
        let sword = try #require(model.allEntries.first { $0.item == Fixture.sword })
        #expect(sword.name == "IronSword")
        #expect(sword.count == 1)
        #expect(sword.weight == 9)
        #expect(sword.value == 25)
        #expect(sword.isEquipped)
        #expect(sword.family == .weapon)

        let cuirass = try #require(model.allEntries.first { $0.item == Fixture.cuirass })
        #expect(cuirass.count == 2)
        #expect(cuirass.totalWeight == 60)
        #expect(cuirass.totalValue == 250)
        #expect(cuirass.isEquipped == false)
    }

    /// A form no loaded plugin describes still gets a row: it is something the
    /// player is genuinely carrying, and hiding it would lose the item.
    @Test func anUndescribedFormStillGetsANamedRow() throws {
        let model = try model()
        let unknown = try #require(model.allEntries.first { $0.item == FormID(0x00FF_FFFF) })
        #expect(unknown.name.isEmpty == false)
        #expect(unknown.family == nil)
        #expect(unknown.weight == 0)
        #expect(unknown.value == 0)
    }

    @Test func rowsSortByNameThenForm() throws {
        let model = try model()
        let names = model.allEntries.map(\.name)
        #expect(names == names
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    /// Carried weight counts gold's stack too — the readout is what the player
    /// carries, and excluding gold from the rows is a display decision, not an
    /// accounting one. The fixture's gold and lockpicks both weigh 0, so the
    /// total is the sword plus two cuirasses.
    @Test func carriedWeightSumsEveryStackIncludingGold() throws {
        let model = try model()
        #expect(model.carriedWeight == 69)
    }

    @Test func anEmptyInventoryProducesNoRowsAndNoGold() throws {
        let model = try InventoryMenuModel.build(inventory: .empty, items: items())
        #expect(model.allEntries.isEmpty)
        #expect(model.gold == 0)
        #expect(model.carriedWeight == 0)
        #expect(model.selectedEntry == nil)
    }

    // MARK: - Categories

    @Test func theFirstCategoryTakesEveryRow() throws {
        let model = try model()
        #expect(model.categoryLabels.first == "All")
        #expect(model.entries.count == model.allEntries.count)
    }

    @Test func aCategoryFiltersToItsOwnFamilies() throws {
        var model = try model()
        let armor = try #require(model.categoryLabels.firstIndex(of: "Armor"))
        model.selectCategory(armor)
        #expect(model.entries.map(\.item) == [Fixture.cuirass])
    }

    /// An item whose family is unknown has to land somewhere reachable, or the
    /// only way to see it is the All tab.
    @Test func anUndescribedFormFiltersAsMiscellaneous() throws {
        var model = try model()
        let misc = try #require(model.categoryLabels.firstIndex(of: "Misc"))
        model.selectCategory(misc)
        #expect(model.entries.contains { $0.item == FormID(0x00FF_FFFF) })
        #expect(model.entries.contains { $0.item == Fixture.lockpick })
    }

    @Test func switchingCategoryWrapsAndReturnsTheRowSelectionToTheTop() throws {
        var model = try model()
        model.moveSelection(by: 2)
        #expect(model.selectedIndex == 2)
        model.moveCategory(by: 1)
        #expect(model.selectedCategoryIndex == 1)
        #expect(model.selectedIndex == 0)
        model.moveCategory(by: -1)
        #expect(model.selectedCategoryIndex == 0)
        model.moveCategory(by: -1)
        #expect(model.selectedCategoryIndex == model.categories.count - 1)
    }

    // MARK: - Navigation

    /// Clamped rather than wrapped: a held key must stop at the last row rather
    /// than silently returning to the first.
    @Test func rowSelectionClampsAtBothEnds() throws {
        var model = try model()
        model.moveSelection(by: -1)
        #expect(model.selectedIndex == 0)
        model.moveSelection(by: 500)
        #expect(model.selectedIndex == model.entries.count - 1)
        #expect(model.selectedEntry != nil)
    }

    @Test func selectingAnOutOfRangeRowChangesNothing() throws {
        var model = try model()
        model.select(1)
        model.select(9999)
        #expect(model.selectedIndex == 1)
    }

    /// A category with no rows must not leave a selection pointing at one.
    @Test func anEmptyCategoryHasNoSelectedEntry() throws {
        var model = try model()
        let books = try #require(model.categoryLabels.firstIndex(of: "Books"))
        model.selectCategory(books)
        #expect(model.entries.isEmpty)
        #expect(model.selectedEntry == nil)
        model.moveSelection(by: 1)
        #expect(model.selectedIndex == 0)
    }

    // MARK: - Live runtime

    /// The `@MainActor` convenience must agree with the plain builder, so the
    /// panel and the movie cannot read two different lists.
    @Test func buildingThroughTheRuntimeMatchesThePlainBuilder() throws {
        let store = WorldStateStore()
        let baselines = try InventoryBaselineFixture.resolver()
        let runtime = InventoryRuntime(store: store, baselines: baselines)
        try runtime.add(Fixture.sword, count: 1, to: .player)
        try runtime.add(Fixture.gold, count: 7, to: .player)
        runtime.equip(Fixture.sword, on: .player)

        let live = InventoryMenuModel.build(holder: .player, runtime: runtime)
        let plain = InventoryMenuModel.build(
            inventory: runtime.inventory(of: .player), items: baselines.items
        )
        #expect(live == plain)
        #expect(live.gold == 7)
        #expect(live.allEntries.map(\.item) == [Fixture.sword])
        #expect(live.allEntries.first?.isEquipped == true)
    }
}
