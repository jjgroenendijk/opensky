// The inventory shell over a fake world: it reads the crosshair, the drop spot,
// and the enchantment hooks through `InventoryWorld`. Decisions are tested in
// `InventoryCoreTests`.

import Foundation
import OpenSkyConditions
@testable import OpenSkyCrimeInterface
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
@testable import OpenSkyMagicInterface
import OpenSkyProgressionInterface
@testable import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct InventoryCoordinatorTests {
    private typealias Fixture = InventoryBaselineFixture
    private typealias Items = WorldItemRuntimeTests

    /// The coordinator, its world and the reference index, all retained,
    /// because the coordinator holds both of the last two weakly.
    private struct Harness {
        let coordinator: InventoryCoordinator
        let world: FakeWorld
        let references: FakeWorldReferences
    }

    private static func harness() throws -> Harness {
        let items = try Items.standardHarness()
        let world = FakeWorld()
        let coordinator = InventoryCoordinator()
        coordinator.attach(world: world)
        try coordinator.wire(
            inventory: items.runtime.inventory,
            references: items.references,
            catalog: EquipmentCatalog.build(from: ESMFile(data: Fixture.pluginBytes())),
            pricing: nil
        )
        return Harness(coordinator: coordinator, world: world, references: items.references)
    }

    private static var looseItem: PlacedInteraction {
        Items.interaction(reference: Items.looseItem, base: Fixture.lockpick, action: .take)
    }

    private static var chest: PlacedInteraction {
        Items.interaction(reference: Items.chestReference, base: Fixture.chest, action: .search)
    }

    /// The live Speech skill sets the factor; the price perks name the merchant.
    @Test func barterPricesReadSpeechAndThePricePerks() throws {
        let harness = try Self.harness()
        let merchant = ReferenceKey.generated(5)
        harness.world.speech = 100
        harness.world.perkFactors[.modBuyPrices] = 0.8
        harness.world.perkFactors[.modSellPrices] = 1.25

        let pricing = harness.coordinator.barterPricing(with: merchant)

        #expect(pricing.speechSkill == 100)
        #expect(pricing.buyModifier == Double(Float(0.8)))
        #expect(pricing.sellModifier == 1.25)
        #expect(harness.world.perkTargets[.modBuyPrices] == merchant)
        #expect(harness.coordinator.barterPricing(with: nil).speechSkill == 100)
    }

    @Test func withoutGameDataEveryActionSaysSo() {
        let coordinator = InventoryCoordinator()
        #expect(coordinator.takeInteractionTarget() == InventoryCore.noRuntimeText)
        #expect(coordinator.dropPlayerItem(nil, count: 1) == InventoryCore.noRuntimeText)
        #expect(coordinator.equipItem(nil, on: .player) == InventoryCore.noEquipmentText)
        #expect(coordinator.itemControlSnapshot == .unavailable)
        #expect(coordinator.inventoryEquipmentSnapshot == .unavailable)
    }

    @Test func theUseKeyTakesTheCrosshairTarget() throws {
        let harness = try Self.harness()
        harness.world.crosshairInteraction = Self.looseItem
        harness.coordinator.handleInteraction(.take)
        let snapshot = harness.coordinator.itemControlSnapshot
        #expect(snapshot.lastActionText == "Took 3 × Fixture.")
        #expect(snapshot.playerStacks.map(\.item) == [Fixture.lockpick])
        // The readout names the item from its record, not by FormID.
        #expect(snapshot.playerStacks.first?.name != Fixture.lockpick.description)
    }

    @Test func aSearchOpensOneSessionUntilItCloses() throws {
        let harness = try Self.harness()
        harness.coordinator.handleInteraction(.search)
        #expect(harness.coordinator.lastActionText == "Nothing under the crosshair to search.")
        harness.world.crosshairInteraction = Self.chest
        harness.coordinator.handleInteraction(.search)
        #expect(harness.coordinator.itemControlSnapshot.containerName == "Fixture")
        #expect(harness.coordinator.closeOpenContainer() == "Closed the container.")
        #expect(harness.coordinator.session == nil)
        #expect(harness.coordinator.closeOpenContainer() == InventoryCore.noContainerText)
    }

    @Test func aDropNeedsAPlacementFromTheWorld() throws {
        let harness = try Self.harness()
        harness.world.crosshairInteraction = Self.looseItem
        harness.coordinator.takeInteractionTarget()
        #expect(harness.coordinator.dropPlayerItem(nil, count: 1)
            == "Drop needs a resident cell; none is loaded.")
        harness.world.placement = DropPlacement(
            location: Items.cell, position: .zero, rotation: .zero
        )
        #expect(harness.coordinator.dropPlayerItem(nil, count: 1).hasPrefix("Dropped 1 ×"))
        let inventory = try #require(harness.coordinator.runtime?.inventory)
        #expect(inventory.count(of: Fixture.lockpick, in: .player) == 2)
    }

    @Test func anEquipRefreshesWornEnchantmentsAfterTheWrite() throws {
        let harness = try Self.harness()
        let inventory = try #require(harness.coordinator.runtime?.inventory)
        try inventory.add(Fixture.cuirass, count: 1, to: .player)
        let text = harness.coordinator.equipItem(nil, on: .player)
        #expect(text.hasPrefix("Equipped "))
        #expect(harness.world.refreshed == [.player])
        #expect(harness.coordinator.equippedReadout(on: .player).count == 1)
        #expect(harness.coordinator.unequipItem(nil, on: .player).hasPrefix("Unequipped "))
        #expect(harness.world.refreshed == [.player, .player])
    }

    @Test func aGrantGoesToTheChosenHolderAndKeepsItsOwnLine() throws {
        let harness = try Self.harness()
        let coordinator = harness.coordinator
        #expect(coordinator.grantItem(Fixture.sword, count: 2, to: .openContainer)
            == "Grant refused: no container is open.")
        #expect(coordinator.grantItem(Fixture.sword, count: 2, to: .player)
            .hasPrefix("Granted 2 ×"))
        #expect(coordinator.runtime?.inventory.count(of: Fixture.sword, in: .player) == 2)
        #expect(coordinator.lastActionText == "No item action yet.")
    }

    @Test func ownershipReadsTheBountyFromTheWorld() throws {
        let harness = try Self.harness()
        #expect(harness.coordinator.targetOwnership() == nil)
        harness.world.crosshairInteraction = Self.chest
        harness.world.bounty = 40
        let ownership = try #require(harness.coordinator.targetOwnership())
        #expect(ownership.reference == Items.chestReference)
        #expect(ownership.bounty == 40)
        #expect(!ownership.isTheft)
    }

    @Test func containerTransfersMoveOneItemEachWay() throws {
        let harness = try Self.harness()
        let coordinator = harness.coordinator
        let chest = try #require(coordinator.containerHolder(for: Self.chest))
        let inventory = try #require(coordinator.runtime?.inventory)
        let recorder = StoryEventRecorder()
        coordinator.storyEvents = recorder
        try inventory.add(Fixture.sword, count: 1, to: .player)
        let stored = try coordinator.transfer(
            .store, item: Fixture.sword, named: "Sword", container: chest, vendor: nil
        )
        #expect(stored == "Stored Sword.")
        #expect(inventory.count(of: Fixture.sword, in: chest) == 1)
        let taken = try coordinator.transfer(
            .take, item: Fixture.sword, named: "Sword", container: chest, vendor: nil
        )
        #expect(taken == "Took Sword.")
        #expect(inventory.count(of: Fixture.sword, in: .player) == 1)
        #expect(coordinator.takeAll(from: chest).hasPrefix("Took all:"))
        let removed = try #require(recorder.events("REMP").first)
        #expect(removed.form == Fixture.sword && removed.actor1 == chest.key)
        #expect(removed.value1 == Float(StoryRemoveType.putInContainer.rawValue))
        let added = recorder.events("AIPL")
        #expect(added.first?.form == Fixture.sword)
        #expect(added.allSatisfy { $0.value1 == Float(StoryAcquireType.container.rawValue) })
    }

    // MARK: - Script natives

    @Test func aScriptEquipGivesTheItemFirst() throws {
        let harness = try Self.harness()
        let coordinator = harness.coordinator
        #expect(coordinator.scriptEquipItem(Fixture.cuirass, on: .player))
        #expect(coordinator.scriptItemCount(Fixture.cuirass, in: .player) == 1)
        #expect(coordinator.equipment?.equipped(on: .player) == [Fixture.cuirass])
        #expect(harness.world.refreshed == [.player])
    }

    @Test func removeAllItemsTakesWornItemsIntoTheOtherContainer() throws {
        let harness = try Self.harness()
        let coordinator = harness.coordinator
        let chest = try #require(harness.references.referenceEntry(formID: Items.chestReference))
        #expect(coordinator.scriptAddItem(Fixture.sword, count: 2, to: .player))
        #expect(coordinator.scriptEquipItem(Fixture.cuirass, on: .player))
        let before = coordinator.scriptItemCount(Fixture.sword, in: chest.key) ?? 0
        #expect(coordinator.scriptRemoveAllItems(from: .player, to: chest.key))
        #expect(coordinator.runtime?.inventory.inventory(of: .player).stacks.isEmpty == true)
        #expect(coordinator.equipment?.equipped(on: .player).isEmpty == true)
        #expect(coordinator.scriptItemCount(Fixture.sword, in: chest.key) == before + 2)
    }

    @Test func setOutfitGivesAndWearsTheOutfit() throws {
        let harness = try Self.harness()
        let coordinator = harness.coordinator
        #expect(coordinator.scriptSetOutfit(Fixture.guardOutfit, on: .player))
        #expect(coordinator.scriptItemCount(Fixture.cuirass, in: .player) == 1)
        #expect(coordinator.equipment?.equipped(on: .player).contains(Fixture.cuirass) == true)
        #expect(coordinator.scriptSetOutfit(Fixture.cuirass, on: .player) == false)
    }

    @Test func removeItemTakesNoMoreThanIsHeld() throws {
        let harness = try Self.harness()
        let coordinator = harness.coordinator
        #expect(coordinator.scriptAddItem(Fixture.sword, count: 1, to: .player))
        #expect(coordinator.scriptRemoveItem(Fixture.sword, count: 5, from: .player, to: nil))
        #expect(coordinator.scriptItemCount(Fixture.sword, in: .player) == 0)
    }

    @Test func dropObjectDropsOnlyWhatThePlayerCarries() throws {
        let harness = try Self.harness()
        let coordinator = harness.coordinator
        #expect(coordinator.scriptAddItem(Fixture.sword, count: 2, to: .player))
        #expect(coordinator.scriptDropObject(Fixture.sword, count: 1, from: .player) == nil)
        harness.world.placement = DropPlacement(
            location: Items.cell, position: .zero, rotation: .zero
        )
        #expect(coordinator.scriptDropObject(Fixture.sword, count: 5, from: .player) != nil)
        #expect(coordinator.scriptItemCount(Fixture.sword, in: .player) == 0)
        #expect(coordinator.scriptDropObject(Fixture.sword, count: 1, from: .player) == nil)
        let chest = ReferenceKey.plugin(name: "test.esp", objectID: 0x99)
        #expect(coordinator.scriptDropObject(Fixture.sword, count: 1, from: chest) == nil)
    }

    @Test func unequipSlotTakesOffWhatCoversTheSlot() throws {
        let harness = try Self.harness()
        let coordinator = harness.coordinator
        #expect(coordinator.scriptSetOutfit(Fixture.guardOutfit, on: .player))
        #expect(coordinator.equipment?.equipped(on: .player).contains(Fixture.cuirass) == true)
        #expect(coordinator.scriptUnequipSlot(29, on: .player) == false)
        #expect(coordinator.scriptUnequipSlot(32, on: .player))
        #expect(coordinator.equipment?.equipped(on: .player).contains(Fixture.cuirass) == false)
        #expect(coordinator.scriptItemCount(Fixture.cuirass, in: .player) == 1)
    }

    @Test func anUnresidentContainerHasNoHolder() throws {
        let harness = try Self.harness()
        let stray = Items.interaction(
            reference: FormID(0xBEEF),
            base: Fixture.chest,
            action: .search
        )
        #expect(harness.coordinator.containerHolder(for: stray) == nil)
    }
}

extension InventoryCoordinatorTests {
    private final class FakeWorld: InventoryWorld {
        var crosshairInteraction: PlacedInteraction?
        var placement: DropPlacement?
        var bounty: Int32 = 0
        var refreshed: [InventoryHolder] = []
        var refreshCount = 0
        var gameDaysPassed: Float?

        func dropPlacement() -> DropPlacement? {
            placement
        }

        func nearestActorEntry() -> RuntimeReferenceEntry? {
            nil
        }

        func containerInteractions() -> [PlacedInteraction] {
            []
        }

        func appearanceSkipReasons(forActor _: FormID) -> [String] {
            []
        }

        func theftBounty(of _: FormID, from _: ReferenceKey) -> Int32 {
            bounty
        }

        func equipmentChanged(on holder: InventoryHolder) {
            refreshed.append(holder)
        }

        func enchantmentLine(of _: FormID, on _: ReferenceKey) -> String? {
            nil
        }

        var enchantmentCacheReadout: EnchantmentCacheReadout {
            .empty
        }

        func refreshInteractionTarget() {
            refreshCount += 1
        }

        var speech: Float?
        var perkFactors: [PerkEntryPoint: Float] = [:]
        private(set) var perkTargets: [PerkEntryPoint: ReferenceKey] = [:]

        func playerSpeechSkill() -> Float? {
            speech
        }

        func perkModified(
            _ value: Float,
            at entryPoint: PerkEntryPoint,
            on _: ReferenceKey,
            subjects: PerkEvaluationSubjects,
            seams _: ConditionContext
        ) -> Float {
            perkTargets[entryPoint] = subjects[.target]
            return value * (perkFactors[entryPoint] ?? 1)
        }
    }
}
