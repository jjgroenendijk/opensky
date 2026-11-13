// The coordinator's parts over the fake world: the script calls, the readouts, the
// condition reads, and the follower and teammate moves. Records are synthetic.

import Foundation
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
@testable import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import Testing

extension InventoryCoordinatorTests {
    private static let stranger = ReferenceKey.generated(0x77)

    /// The script calls answer for the player and refuse a reference no cell knows.
    @Test func scriptCallsReadThePlayersInventory() throws {
        let scripts = try Self.harness().coordinator.scriptItems
        #expect(scripts.scriptAddItem(Fixture.sword, count: 1, to: .player))
        #expect(scripts.scriptItemCount(Fixture.sword, in: .player) == 1)
        #expect(scripts.scriptIsEquipped(Fixture.sword, on: .player) == false)
        _ = scripts.scriptGoldValue(of: Fixture.sword)
        _ = scripts.scriptEquippedWeapon(on: .player, leftHand: false)
        _ = scripts.scriptEquippedShield(on: .player)
        _ = scripts.scriptUnequipAll(on: .player)
        _ = scripts.scriptUnequipItem(Fixture.sword, on: .player)
        _ = scripts.scriptSetOutfit(Fixture.cuirass, on: .player)
        _ = scripts.scriptBaselineInventory(of: .player)
        #expect(scripts.scriptIsEquipped(Fixture.sword, on: Self.stranger) == nil)
        #expect(scripts.scriptEquippedShield(on: Self.stranger) == nil)
        #expect(!scripts.scriptAddItem(Fixture.sword, count: 1, to: Self.stranger))
    }

    /// The condition reads, the readouts, and the death items over the player.
    @Test func thePartsAnswerForThePlayer() throws {
        let coordinator = try Self.harness().coordinator
        _ = coordinator.itemConditions.conditionEquipment(of: .player)
        _ = coordinator.itemConditions.conditionKeywordCounts(of: .player)
        #expect(coordinator.itemConditions.conditionEquipment(of: Self.stranger) == nil)
        _ = coordinator.craftingReadout.craftingSnapshot
        _ = coordinator.craftingReadout.qualityName(1, of: Fixture.sword)
        _ = coordinator.itemPanels.inventoryEquipmentSnapshot
        _ = coordinator.itemPanels.itemControlSnapshot
        #expect(coordinator.itemPanels.targetOwnership() == nil)
        _ = coordinator.deathItems.grantDeathItem(to: .player, actorLevel: 1)
        #expect(coordinator.containerTrade.tradeTexts == coordinator.texts.trade)
        #expect(coordinator.itemCards.menuTexts == coordinator.texts.menu)
    }

    /// A follower that no cell knows takes nothing.
    @Test func followerAndTeammateMovesNeedKnownHolders() throws {
        let coordinator = try Self.harness().coordinator
        let takes = coordinator.followerTakes
        #expect(!takes.followerTakeAll(from: Self.stranger, by: .player).value)
        #expect(!takes.followerPickUp(Self.stranger, by: .player))
        let teammate = InventoryHolder(key: Self.stranger, owner: .actor(base: FormID(0x20)))
        let trades = coordinator.teammateTrades
        _ = trades.teammateRefusal(.take, item: Fixture.sword, count: 1, teammate: teammate)
        _ = trades.takeAllFromTeammate(teammate)
        #expect(trades.teammateOutfit(of: teammate).isEmpty)
    }

    /// The use key with nothing under the crosshair does nothing, and a closed
    /// crafting session says so.
    @Test func theUseKeyWithNothingAimedDoesNothing() throws {
        let coordinator = try Self.harness().coordinator
        for action in [InteractionAction.take, .search, .harvest, .use, .open] {
            #expect(coordinator.itemActions.handleInteraction(action).isEmpty)
        }
        _ = coordinator.craftingBench.harvestInteractionTarget()
        _ = coordinator.craftingBench.craft(ResolvedFormID(plugin: "base.esm", objectID: 1))
        _ = coordinator.craftingBench.closeCraftingSession()
    }
}
