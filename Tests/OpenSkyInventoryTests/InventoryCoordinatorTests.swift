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
    /// because the item runtime holds the reference index weakly.
    private struct Harness {
        let coordinator: InventoryCoordinator
        let world: FakeWorld
        let references: FakeWorldReferences
    }

    private static func harness(seams: InventorySeams = InventorySeams()) throws -> Harness {
        let items = try Items.standardHarness()
        let world = FakeWorld()
        var data = InventorySessionData(items: WorldItemRuntime(
            inventory: items.runtime.inventory, references: items.references
        ))
        data.equipment = try EquipmentCatalog.build(from: ESMFile(data: Fixture.pluginBytes()))
        let coordinator = InventoryCoordinator(
            world: world, lockWorld: FakeLockWorld(), data: data, seams: seams
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
        let coordinator = InventoryCoordinator(
            world: FakeWorld(), lockWorld: FakeLockWorld(), data: nil
        )
        #expect(coordinator.takeInteractionTarget().text == InventoryCore.noRuntimeText)
        #expect(coordinator.dropPlayerItem(nil, count: 1).text == InventoryCore.noRuntimeText)
        #expect(coordinator.equipItem(nil, on: .player).value.text == InventoryCore.noEquipmentText)
        #expect(coordinator.itemControlSnapshot == .unavailable)
        #expect(coordinator.inventoryEquipmentSnapshot == .unavailable)
    }

    @Test func theUseKeyTakesTheCrosshairTarget() throws {
        let harness = try Self.harness()
        harness.world.crosshairInteraction = Self.looseItem
        _ = harness.coordinator.handleInteraction(.take)
        let snapshot = harness.coordinator.itemControlSnapshot
        #expect(snapshot.lastActionText == "Took 3 × Fixture.")
        #expect(snapshot.playerStacks.map(\.item) == [Fixture.lockpick])
        // The readout names the item from its record, not by FormID.
        #expect(snapshot.playerStacks.first?.name != Fixture.lockpick.description)
    }

    @Test func aSearchOpensOneSessionUntilItCloses() throws {
        let harness = try Self.harness()
        _ = harness.coordinator.handleInteraction(.search)
        #expect(harness.coordinator.lastAction.text == "Nothing under the crosshair to search.")
        harness.world.crosshairInteraction = Self.chest
        _ = harness.coordinator.handleInteraction(.search)
        #expect(harness.coordinator.itemControlSnapshot.containerName == "Fixture")
        #expect(harness.coordinator.closeOpenContainer().text == "Closed the container.")
        #expect(harness.coordinator.session == nil)
        #expect(harness.coordinator.closeOpenContainer().text == InventoryCore.noContainerText)
    }

    @Test func aDropNeedsAPlacementFromTheWorld() throws {
        let harness = try Self.harness()
        harness.world.crosshairInteraction = Self.looseItem
        harness.coordinator.takeInteractionTarget()
        #expect(harness.coordinator.dropPlayerItem(nil, count: 1).text
            == "Drop needs a resident cell; none is loaded.")
        harness.world.placement = DropPlacement(
            location: Items.cell, position: .zero, rotation: .zero
        )
        #expect(harness.coordinator.dropPlayerItem(nil, count: 1).text.hasPrefix("Dropped 1 ×"))
        let inventory = try #require(harness.coordinator.runtime?.inventory)
        #expect(inventory.count(of: Fixture.lockpick, in: .player) == 2)
    }

    @Test func anEquipRefreshesWornEnchantmentsAfterTheWrite() throws {
        let harness = try Self.harness()
        let inventory = try #require(harness.coordinator.runtime?.inventory)
        try inventory.add(Fixture.cuirass, count: 1, to: .player)
        let equipped = harness.coordinator.equipItem(nil, on: .player)
        #expect(equipped.value.text.hasPrefix("Equipped "))
        #expect(equipped.commands == [.equipmentChanged(.player)])
        #expect(harness.coordinator.equippedReadout(on: .player).count == 1)
        let unequipped = harness.coordinator.unequipItem(nil, on: .player)
        #expect(unequipped.value.text.hasPrefix("Unequipped "))
        #expect(unequipped.commands == [.equipmentChanged(.player)])
    }

    @Test func wornArmourWeighsWhatTheArmourWeightPerksSay() throws {
        let harness = try Self.harness()
        let coordinator = harness.coordinator
        #expect(coordinator.scriptEquipItem(Fixture.cuirass, on: .player).value)
        try #require(coordinator.runtime?.inventory).add(Fixture.helmet, count: 1, to: .player)
        #expect(coordinator.playerCarriedWeight == 35)
        harness.world.perkFactors[.modArmorWeight] = 0.5
        #expect(coordinator.playerCarriedWeight == 20)
        #expect(coordinator.playerWornArmourWeight == 15)
    }

    @Test func theHarvestPerkSetsHowManyIngredientsAPlantGives() throws {
        let harness = try Self.harness()
        let plant = HarvestTests.flora(HarvestTests.plant, produce: Fixture.lockpick)
        #expect(harness.coordinator.harvestCount(of: plant) == 1)
        harness.world.perkFactors[.modIngredientsHarvested] = 2
        #expect(harness.coordinator.harvestCount(of: plant) == 2)
    }

    @Test func aPerkActivateLabelReplacesTheAuthoredOne() throws {
        let harness = try Self.harness()
        let plant = HarvestTests.flora(HarvestTests.plant, produce: Fixture.lockpick)
        #expect(harness.coordinator.labelled(plant).actionLabel == "Harvest")
        harness.world.activateLabel = "Feed"
        #expect(harness.coordinator.labelled(plant).actionLabel == "Feed")
    }

    @Test func aGrantGoesToTheChosenHolderAndKeepsItsOwnLine() throws {
        let harness = try Self.harness()
        let coordinator = harness.coordinator
        #expect(coordinator.grantItem(Fixture.sword, count: 2, to: .openContainer).text
            == "Grant refused: no container is open.")
        #expect(coordinator.grantItem(Fixture.sword, count: 2, to: .player).text
            .hasPrefix("Granted 2 ×"))
        #expect(coordinator.runtime?.inventory.count(of: Fixture.sword, in: .player) == 2)
        #expect(coordinator.lastAction.text == "No item action yet.")
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
        let recorder = StoryEventRecorder()
        let harness = try Self.harness(seams: InventorySeams(storyEvents: recorder))
        let coordinator = harness.coordinator
        let chest = try #require(coordinator.containerHolder(for: Self.chest))
        let inventory = try #require(coordinator.runtime?.inventory)
        try inventory.add(Fixture.sword, count: 1, to: .player)
        let stored = try coordinator.transfer(
            .store, item: Fixture.sword, named: "Sword", container: chest, vendor: nil
        )
        #expect(stored.text(texts: .vanilla) == "Stored Sword.")
        #expect(inventory.count(of: Fixture.sword, in: chest) == 1)
        let taken = try coordinator.transfer(
            .take, item: Fixture.sword, named: "Sword", container: chest, vendor: nil
        )
        #expect(taken.text(texts: .vanilla) == "Took Sword.")
        #expect(inventory.count(of: Fixture.sword, in: .player) == 1)
        #expect(coordinator.takeAll(from: chest).text.hasPrefix("Took all:"))
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
        #expect(coordinator.scriptEquipItem(Fixture.cuirass, on: .player)
            == InventoryResult(true, commands: [.equipmentChanged(.player)]))
        #expect(coordinator.scriptItemCount(Fixture.cuirass, in: .player) == 1)
        #expect(coordinator.equipment?.equipped(on: .player) == [Fixture.cuirass])
    }

    @Test func removeAllItemsTakesWornItemsIntoTheOtherContainer() throws {
        let harness = try Self.harness()
        let coordinator = harness.coordinator
        let chest = try #require(harness.references.referenceEntry(formID: Items.chestReference))
        #expect(coordinator.scriptAddItem(Fixture.sword, count: 2, to: .player))
        #expect(coordinator.scriptEquipItem(Fixture.cuirass, on: .player).value)
        let before = coordinator.scriptItemCount(Fixture.sword, in: chest.key) ?? 0
        #expect(coordinator.scriptRemoveAllItems(from: .player, to: chest.key).value)
        #expect(coordinator.runtime?.inventory.inventory(of: .player).stacks.isEmpty == true)
        #expect(coordinator.equipment?.equipped(on: .player).isEmpty == true)
        #expect(coordinator.scriptItemCount(Fixture.sword, in: chest.key) == before + 2)
    }

    @Test func setOutfitGivesAndWearsTheOutfit() throws {
        let harness = try Self.harness()
        let coordinator = harness.coordinator
        #expect(coordinator.scriptSetOutfit(Fixture.guardOutfit, on: .player).value)
        #expect(coordinator.scriptItemCount(Fixture.cuirass, in: .player) == 1)
        #expect(coordinator.equipment?.equipped(on: .player).contains(Fixture.cuirass) == true)
        #expect(coordinator.scriptSetOutfit(Fixture.cuirass, on: .player).value == false)
    }

    @Test func removeItemTakesNoMoreThanIsHeld() throws {
        let harness = try Self.harness()
        let coordinator = harness.coordinator
        #expect(coordinator.scriptAddItem(Fixture.sword, count: 1, to: .player))
        #expect(coordinator.scriptRemoveItem(Fixture.sword, count: 5, from: .player, to: nil).value)
        #expect(coordinator.scriptItemCount(Fixture.sword, in: .player) == 0)
    }

    @Test func dropObjectDropsOnlyWhatThePlayerCarries() throws {
        let harness = try Self.harness()
        let coordinator = harness.coordinator
        #expect(coordinator.scriptAddItem(Fixture.sword, count: 2, to: .player))
        #expect(coordinator.scriptDropObject(Fixture.sword, count: 1, from: .player).value == nil)
        harness.world.placement = DropPlacement(
            location: Items.cell, position: .zero, rotation: .zero
        )
        #expect(coordinator.scriptDropObject(Fixture.sword, count: 5, from: .player).value != nil)
        #expect(coordinator.scriptItemCount(Fixture.sword, in: .player) == 0)
        #expect(coordinator.scriptDropObject(Fixture.sword, count: 1, from: .player).value == nil)
        let chest = ReferenceKey.plugin(name: "test.esp", objectID: 0x99)
        #expect(coordinator.scriptDropObject(Fixture.sword, count: 1, from: chest).value == nil)
    }

    @Test func unequipSlotTakesOffWhatCoversTheSlot() throws {
        let harness = try Self.harness()
        let coordinator = harness.coordinator
        #expect(coordinator.scriptSetOutfit(Fixture.guardOutfit, on: .player).value)
        #expect(coordinator.equipment?.equipped(on: .player).contains(Fixture.cuirass) == true)
        #expect(coordinator.scriptUnequipSlot(29, on: .player).value == false)
        #expect(coordinator.scriptUnequipSlot(32, on: .player).value)
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

// MARK: - Pickpocket

extension InventoryCoordinatorTests {
    private final class SkillRecorder: SkillUseReporting {
        var uses: [SkillUseEvent] = []

        func reportSkillUse(_ use: SkillUseEvent) -> Float {
            uses.append(use)
            return use.amount
        }
    }

    /// Both skills, the weight, and being seen feed the chance (UESP "Skyrim:Pickpocket").
    @Test func thePickpocketChanceReadsBothSkillsAndDetection() throws {
        let harness = try Self.harness()
        let chest = try #require(harness.coordinator.containerHolder(for: Self.chest))
        harness.world.pickpocketSkills = [.player: 50, chest.key: 30]
        let weight = harness.coordinator.runtime?.inventory.baselines.items
            .definition(Fixture.sword)?.weight ?? 0
        let settings = PickpocketSettings.vanilla
        let unseen = settings.clamped(settings.baseChance(PickpocketAttempt(
            thiefSkill: 50, targetSkill: 30, weight: weight
        )))
        #expect(harness.coordinator.pickpocketChance(of: Fixture.sword, count: 1, from: chest)
            == unseen)
        harness.world.detected = true
        #expect(harness.coordinator.pickpocketChance(of: Fixture.sword, count: 1, from: chest)
            == settings.clamped(unseen - settings.detectedPenalty))
    }

    /// A roll under the chance moves the item, marked stolen, and teaches Pickpocket
    /// by its value; a roll over it moves nothing.
    @Test func aPickpocketRollDecidesTheTake() throws {
        let recorder = SkillRecorder()
        let harness = try Self.harness(seams: InventorySeams(skillUses: recorder))
        let coordinator = harness.coordinator
        let chest = try #require(coordinator.containerHolder(for: Self.chest))
        let inventory = try #require(coordinator.runtime?.inventory)
        try inventory.add(Fixture.sword, count: 1, to: chest)
        harness.world.pickpocketSkills = [.player: 100, chest.key: 15]

        let caught = coordinator.pickpocket(Fixture.sword, named: "Sword", from: chest, roll: 99)
        #expect(caught.wasCaught)
        #expect(inventory.count(of: Fixture.sword, in: .player) == 0)

        let took = coordinator.pickpocket(Fixture.sword, named: "Sword", from: chest, roll: 0)
        guard case .took = took else {
            Issue.record("expected a take, got \(took)")
            return
        }
        #expect(inventory.stolenCount(of: Fixture.sword, in: .player) == 1)
        let value = inventory.baselines.items.definition(Fixture.sword)?.value ?? 0
        #expect(recorder.uses.map(\.action) == [.pickpocket])
        #expect(recorder.uses.first?.amount == Float(value))
    }

    /// A target that caught the player refuses for two game days (UESP "Skyrim:Pickpocket").
    @Test func aCatchRefusesTheTargetForTwoDays() throws {
        let harness = try Self.harness()
        let coordinator = harness.coordinator
        let chest = try #require(coordinator.containerHolder(for: Self.chest))
        try #require(coordinator.runtime?.inventory).add(Fixture.sword, count: 1, to: chest)
        harness.world.gameDaysPassed = 10
        #expect(!coordinator.pickpocketRefused(by: chest.key))

        _ = coordinator.pickpocket(Fixture.sword, named: "Sword", from: chest, roll: 99)
        harness.world.gameDaysPassed = 11.9
        #expect(coordinator.pickpocketRefused(by: chest.key))
        harness.world.gameDaysPassed = 12
        #expect(!coordinator.pickpocketRefused(by: chest.key))
    }

    /// Worn items stay put without a Can Pickpocket Equipped Item perk.
    @Test func anEquippedItemNeedsThePerk() throws {
        let harness = try Self.harness()
        let coordinator = harness.coordinator
        #expect(coordinator.scriptEquipItem(Fixture.cuirass, on: .player).value)
        let pocket = try #require(coordinator.runtime?.player)
        #expect(coordinator.pickpocket(Fixture.cuirass, named: "Cuirass", from: pocket, roll: 0)
            == .equipped("Cuirass"))
    }
}

extension InventoryCoordinatorTests {
    private final class FakeWorld: InventoryWorld {
        var activateLabel: String?
        var crosshairInteraction: PlacedInteraction?
        var placement: DropPlacement?
        var bounty: Int32 = 0
        var gameDaysPassed: Float?
        var caughtDays: [ReferenceKey: Float] = [:]
        var caughtFactions: [ReferenceKey: ReferenceKey] = [:]

        func pickpocketCaughtDay(of key: ReferenceKey) -> Float? {
            caughtDays[key]
        }

        func notePickpocketCatch(
            on day: Float?, chargedTo faction: ReferenceKey?, by key: ReferenceKey
        ) {
            caughtDays[key] = day
            caughtFactions[key] = faction
        }

        func perkActivateLabel(for _: FormID) -> String? {
            activateLabel
        }

        func dropPlacement() -> DropPlacement? {
            placement
        }

        func nearestActorEntry() -> RuntimeReferenceEntry? {
            nil
        }

        func appearanceSkipReasons(forActor _: FormID) -> [String] {
            []
        }

        func theftBounty(of _: FormID, from _: ReferenceKey) -> Int32 {
            bounty
        }

        func enchantmentLine(of _: FormID, on _: ReferenceKey) -> String? {
            nil
        }

        var enchantmentCacheReadout: EnchantmentCacheReadout {
            .empty
        }

        var speech: Float?
        var pickpocketSkills: [ReferenceKey: Float] = [:]
        var detected = false
        var perkFactors: [PerkEntryPoint: Float] = [:]
        private(set) var perkTargets: [PerkEntryPoint: ReferenceKey] = [:]

        func playerSpeechSkill() -> Float? {
            speech
        }

        func pickpocketSkill(of key: ReferenceKey) -> Float? {
            pickpocketSkills[key]
        }

        func detectsPlayer(_: ReferenceKey) -> Bool {
            detected
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
