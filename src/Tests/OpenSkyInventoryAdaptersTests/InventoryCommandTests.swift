// The Papyrus part forwards each script call to the inventory and runs the commands it returns.

import OpenSkyFormatsESM
import OpenSkyInventoryAdapters
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct InventoryCommandTests {
    private let host = InventoryHost()
    private var adapter: InventoryWorldAdapter {
        InventoryWorldAdapter(game: host)
    }

    private static let item = FormID(0x30)
    private static let actor = InventoryAdapterFixture.key
    private static let done = InventoryResult(true, commands: [.showNotice("Done")])

    @Test func eachCommandReachesItsSystem() {
        let target = InventoryAdapterFixture.target(InventoryAdapterFixture.interaction(.open))
        let holder = InventoryHolder(key: Self.actor, owner: .actor(base: FormID(0x20)))
        host.fakeStreamer.interactionTarget = target
        host.fakeMagic.equipmentChangedResult = WornEnchantmentReport.none
        host.fakeInventory.labelledResult = InventoryAdapterFixture.interaction(.take)
        adapter.run([.equipmentChanged(holder), .refreshInteractionTarget, .showNotice("Locked")])
        #expect(host.fakeMagic.equipmentChangedCalls == [holder])
        #expect(host.fakeInventory.labelledCalls == [target.interaction])
        #expect(host.fakeHUD.updateTargetCalls.first??.interaction.action == .take)
        #expect(host.fakeHUD.showNotificationCalls == ["Locked"])
    }

    @Test func noTargetRefreshesToNoTarget() {
        adapter.commands.run([.refreshInteractionTarget])
        #expect(host.fakeHUD.updateTargetCalls.count == 1)
        #expect(host.fakeInventory.labelledCalls.isEmpty)
    }

    @Test func aResultHandsBackItsValueAfterItsCommands() {
        #expect(adapter.run(Self.done))
        #expect(host.fakeHUD.showNotificationCalls == ["Done"])
    }

    @Test func scriptChangesRunTheirCommands() {
        let inventory = host.fakeInventory
        inventory.scriptRemoveItemResult = Self.done
        inventory.scriptUnequipSlotResult = Self.done
        inventory.scriptDropObjectResult = InventoryResult(
            Self.actor,
            commands: [.showNotice("Done")]
        )
        inventory.scriptRemoveAllItemsResult = Self.done
        inventory.scriptEquipItemResult = Self.done
        inventory.scriptUnequipItemResult = Self.done
        inventory.scriptSetOutfitResult = Self.done
        inventory.scriptUnequipAllResult = Self.done
        #expect(adapter.removeItem(Self.item, count: 2, from: .player, to: Self.actor))
        #expect(adapter.unequipSlot(32, on: Self.actor))
        #expect(adapter.dropItem(Self.item, count: 1, from: .player) == Self.actor)
        #expect(adapter.removeAllItems(from: Self.actor, to: .player, removeQuestItems: false))
        #expect(adapter.equipItem(Self.item, on: Self.actor))
        #expect(adapter.unequipItem(Self.item, on: Self.actor))
        #expect(adapter.setOutfit(Self.item, on: Self.actor))
        #expect(adapter.unequipAll(on: Self.actor))
        #expect(host.fakeHUD.showNotificationCalls.count == 8)
        #expect(inventory.scriptRemoveItemCalls.map(\.other) == [Self.actor])
        #expect(inventory.scriptUnequipSlotCalls.map(\.slot) == [32])
    }

    @Test func scriptQuestionsReadTheInventory() {
        let inventory = host.fakeInventory
        inventory.scriptAddItemResult = true
        inventory.scriptItemCountResult = 3
        inventory.scriptIsEquippedResult = true
        inventory.scriptEquippedWeaponResult = .some(Self.item)
        inventory.scriptEquippedShieldResult = .some(nil)
        inventory.scriptGoldValueResult = 25
        inventory.learnIngredientEffectsResult = true
        inventory.learnNextIngredientEffectResult = 2
        inventory.isHostileItemResult = false
        #expect(adapter.addItem(Self.item, count: 3, to: .player))
        #expect(adapter.baselineInventory(of: Self.actor) == nil)
        #expect(adapter.itemCount(Self.item, in: .player) == 3)
        #expect(adapter.isEquipped(Self.item, on: Self.actor) == true)
        #expect(adapter.equippedWeapon(on: Self.actor, leftHand: true) == .some(Self.item))
        #expect(adapter.equippedShield(on: Self.actor) == .some(nil))
        #expect(adapter.goldValue(of: Self.item) == 25)
        #expect(adapter.learnIngredientEffects(Self.item, indices: [0]))
        #expect(adapter.learnNextIngredientEffect(Self.item) == 2)
        #expect(adapter.isHostileItem(Self.item) == false)
        #expect(inventory.scriptBaselineInventoryCalls == [Self.actor])
        #expect(inventory.scriptEquippedWeaponCalls.map(\.leftHand) == [true])
        #expect(inventory.learnIngredientEffectsCalls.map(\.indices) == [[0]])
    }
}
