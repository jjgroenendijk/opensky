// Favourites and hotkeys: marking keeps the order, a hotkey needs a carried
// favourite, and the item card reads the record and the marks.

import Foundation
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
@testable import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct FavouritesTests {
    private typealias Fixture = InventoryBaselineFixture

    @Test func unmarkingFreesTheHotkeyAndBindingMarks() throws {
        let sword = Fixture.sword
        let pick = Fixture.lockpick
        let bound = try #require(FavouritesState().toggling(pick).binding(sword, to: 2))
        #expect(bound.items == [pick, sword])
        #expect(bound.hotkey(of: sword) == 2)
        let moved = try #require(bound.binding(sword, to: 5))
        #expect(moved.hotkeys == [5: sword])
        #expect(moved.toggling(sword).hotkeys.isEmpty)
        #expect(bound.binding(sword, to: 9) == nil)
        #expect(FavouritesState(items: [pick, pick], hotkeys: [0: pick, 4: sword]).hotkeys
            .isEmpty)
    }

    @Test func aHotkeyNamesOnlyACarriedFavourite() throws {
        let items = try WorldItemRuntimeTests.standardHarness()
        let coordinator = InventoryCoordinator(
            world: FakeAlchemyWorld(), locks: LockCoordinator(world: FakeLockWorld())
        )
        coordinator.wire(
            inventory: items.runtime.inventory, references: items.references,
            catalog: nil, pricing: nil
        )
        #expect(coordinator.hotkeyItem(1) == .failure(.emptySlot(1)))
        #expect(coordinator.bindHotkey(1, to: Fixture.sword) == .bound("IronSword", slot: 1))
        #expect(coordinator.hotkeyItem(1) == .failure(.notCarried("IronSword")))
        try items.runtime.inventory.add(Fixture.sword, count: 1, to: .player)
        #expect(coordinator.hotkeyItem(1) == .success(Fixture.sword))
        #expect(coordinator.hotkeyItem(0) == .failure(.badSlot(0)))
        #expect(coordinator.toggleFavourite(Fixture.sword) == .unmarked("IronSword"))
        #expect(coordinator.hotkeyItem(1) == .failure(.emptySlot(1)))
    }

    @Test func theCardReadsDamageEffectsAndMarks() throws {
        let store = WorldStateStore()
        let inventory = try InventoryRuntime(store: store, baselines: AlchemyFixture.resolver())
        let references = FakeWorldReferences(entries: [], cell: WorldItemRuntimeTests.cell)
        let coordinator = InventoryCoordinator(
            world: FakeAlchemyWorld(), locks: LockCoordinator(world: FakeLockWorld())
        )
        coordinator.wire(inventory: inventory, references: references, catalog: nil, pricing: nil)
        try coordinator.wireAlchemy(
            effects: AlchemyFixture.effects(), pluginName: AlchemyFixture.pluginName,
            settings: .vanilla, texts: .vanilla
        )
        let sword = try #require(coordinator.itemCard(for: Fixture.sword))
        #expect(sword.kind == "Weapon")
        #expect(sword.damage == 7)
        let poison = try #require(coordinator.itemCard(for: AlchemyFixture.poison))
        #expect(poison.kind == "Poison")
        #expect(poison.effects == ["Damage Health 10"])
        coordinator.learnEatenIngredient(AlchemyFixture.wheat)
        coordinator.bindHotkey(4, to: AlchemyFixture.wheat)
        let wheat = try #require(coordinator.itemCard(for: AlchemyFixture.wheat))
        #expect(wheat.effects == ["Restore Health", "?"])
        #expect(wheat.lines.last == "favourite, hotkey 4")
    }
}
