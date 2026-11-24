// A follower dresses again when armour or a weapon changes hands with the player: it
// wears the best armour in each slot and its best weapon.

import Foundation
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
import Testing

@MainActor
struct TeammateRedressTests {
    private typealias Fixture = InventoryBaselineFixture

    @Test func aGiftOfArmourDressesTheFollower() throws {
        let harness = try InventoryCoordinatorTests.harness()
        let coordinator = harness.coordinator
        let inventory = try #require(coordinator.equipment?.inventory)
        let follower = InventoryHolder(key: .generated(42), owner: .generated)
        try inventory.add(Fixture.helmet, count: 1, to: follower)
        try inventory.add(Fixture.cuirass, count: 1, to: follower)
        try inventory.add(Fixture.sword, count: 1, to: follower)
        try inventory.add(Fixture.lockpick, count: 1, to: follower)
        let trades = coordinator.teammateTrades
        #expect(!trades.redress(follower, after: Fixture.lockpick))
        #expect(coordinator.equipment?.equipped(on: follower).isEmpty == true)
        #expect(trades.redress(follower, after: Fixture.cuirass))
        let worn = Set(coordinator.equipment?.equipped(on: follower) ?? [])
        #expect(worn == [Fixture.helmet, Fixture.cuirass, Fixture.sword])
    }

    @Test func takingEverythingDressesWhatIsLeft() throws {
        let harness = try InventoryCoordinatorTests.harness()
        let coordinator = harness.coordinator
        let inventory = try #require(coordinator.equipment?.inventory)
        let follower = InventoryHolder(key: .generated(43), owner: .generated)
        try inventory.add(Fixture.cuirass, count: 1, to: follower)
        _ = try coordinator.equipment?.equip(Fixture.cuirass, on: follower)
        _ = coordinator.teammateTrades.takeAllFromTeammate(follower)
        #expect(inventory.count(of: Fixture.cuirass, in: .player) == 1)
        #expect(coordinator.equipment?.equipped(on: follower).isEmpty == true)
    }
}
