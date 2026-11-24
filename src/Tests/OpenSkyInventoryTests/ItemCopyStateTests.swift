// Item copies: the best-first order, the plainest copies leaving first, a charge that
// keeps its place, and a filled gem that moves with its soul.

import Foundation
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
import OpenSkyMagicInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct ItemCopyStateTests {
    private let item = FormID(0x0100)

    @Test func copiesReadBestFirstAndPlainPastTheList() {
        let state = ItemCopyState(copies: [item.rawValue: [ItemCopy(soul: 2), ItemCopy(level: 3)]])
        #expect(state.copies(of: item, held: 3) == [ItemCopy(level: 3), ItemCopy(soul: 2), .plain])
        #expect(state.copies(of: item, held: 1) == [ItemCopy(level: 3)])
        #expect(ItemCopyState(copies: [item.rawValue: [.plain]]).isEmpty)
    }

    /// A spent copy stays ahead of a plain one, so the copy an equip wears keeps its charge.
    @Test func aSpentCopyKeepsItsPlace() {
        let state = ItemCopyState(copies: [item.rawValue: [ItemCopy(charge: 10)]])
        #expect(state.bestCopy(of: item, held: 2) == ItemCopy(charge: 10))
        let edited = state.editing(item, held: 2, where: { $0.charge != nil }, { $0.charge = 5 })
        #expect(edited?.copies(of: item, held: 2) == [ItemCopy(charge: 5), .plain])
    }

    @Test func thePlainestCopiesLeaveFirst() {
        let state = ItemCopyState(copies: [item.rawValue: [ItemCopy(soul: 1)]])
        let (remaining, taken) = state.taking(1, of: item, held: 2)
        #expect(taken == [.plain])
        #expect(remaining.copies(of: item, held: 1) == [ItemCopy(soul: 1)])
        #expect(remaining.giving([ItemCopy(soul: 5)], of: item, held: 1)
            .copies(of: item, held: 2) == [ItemCopy(soul: 5), ItemCopy(soul: 1)])
    }

    /// A filled gem given to a chest arrives filled, and the giver keeps only the rest.
    @Test func aTransferCarriesTheCopy() throws {
        let store = WorldStateStore()
        let inventory = try InventoryRuntime(
            store: store,
            baselines: InventoryBaselineFixture.resolver()
        )
        let gem = InventoryBaselineFixture.lockpick
        let chest = InventoryHolder(
            key: .plugin(name: "skyrim.esm", objectID: 0x0BAE),
            owner: .container(base: InventoryBaselineFixture.emptyChest),
            cell: nil
        )
        try inventory.add(gem, count: 2, to: .player, copies: [ItemCopy(soul: 3)])
        #expect(inventory.copies(of: gem, in: .player) == [ItemCopy(soul: 3), .plain])
        #expect(inventory.editCopy(of: gem, in: .player, where: { $0.isPlain }, { $0.soul = 4 }))
        try inventory.transfer(gem, count: 1, from: .player, to: chest)
        #expect(inventory.copies(of: gem, in: chest) == [ItemCopy(soul: 3)])
        #expect(inventory.copies(of: gem, in: .player) == [ItemCopy(soul: 4)])
    }

    /// The chosen copy reads first, and a move takes the preferred copies before the plainest.
    @Test func theChosenCopyLeadsAndAPreferredCopyLeavesFirst() {
        var chosen = ItemCopy(soul: 1)
        chosen.isChosen = true
        let state = ItemCopyState(copies: [item.rawValue: [ItemCopy(level: 3), chosen]])
        #expect(state.copies(of: item, held: 3).first == chosen)
        let (remaining, taken) = state.taking(1, of: item, held: 3, preferring: ItemCopy(soul: 1))
        #expect(taken == [ItemCopy(soul: 1)])
        #expect(remaining.copies(of: item, held: 2) == [ItemCopy(level: 3), .plain])
    }

    /// A menu action on one row's copy wears that copy and moves it first.
    @Test func actingOnARowMovesThatRowsCopy() throws {
        let inventory = try InventoryRuntime(
            store: WorldStateStore(), baselines: InventoryBaselineFixture.resolver()
        )
        let sword = InventoryBaselineFixture.sword
        let chest = InventoryHolder(key: .generated(5), owner: .generated)
        var named = ItemCopy()
        named.name = "Biter"
        try inventory.add(sword, count: 3, to: .player, copies: [ItemCopy(level: 2), named])
        try inventory.acting(on: named, of: sword, in: .player) {
            #expect(inventory.copies(of: sword, in: .player).first?.name == "Biter")
            try inventory.transfer(sword, count: 1, from: .player, to: chest)
        }
        #expect(inventory.copies(of: sword, in: chest) == [named])
        #expect(inventory.copies(of: sword, in: .player) == [ItemCopy(level: 2), .plain])
        #expect(inventory.acting(on: nil, of: sword, in: .player) { 7 } == 7)
    }

    /// A made enchantment adds its worth to the copy, and a temper multiplies the sum.
    @Test func aCopyIsWorthItsEnchantmentAndTemper() throws {
        let store = WorldStateStore()
        let inventory = try InventoryRuntime(
            store: store, baselines: InventoryBaselineFixture.resolver()
        )
        let cuirass = InventoryBaselineFixture.cuirass
        let made = MadeEnchantment(
            bases: [.player], powers: [1], capacity: 0, costPerUse: 30.6, name: "Fortify"
        )
        let (enchanting, id) = EnchantingState().making(made)
        _ = store.set(enchanting, for: .player)
        let plain = inventory.value(of: cuirass, copy: .plain)
        let enchanted = ItemCopy(enchantment: id)
        #expect(inventory.value(of: cuirass, copy: enchanted) == plain + 31)
        #expect(inventory
            .value(of: cuirass, copy: ItemCopy(enchantment: FormID(0xFF60_0099))) == plain)
        #expect(inventory.value(of: cuirass, copy: ItemCopy(level: 2)) >= plain)
        try inventory.add(cuirass, count: 2, to: .player, copies: [enchanted])
        #expect(inventory.bestCopyValue(of: cuirass, in: .player) == plain + 31)
    }
}
