// Arrest outcomes (issue #505): paying a fine and serving a sentence, and what
// both do to the ledger, the player's gold and stolen goods. Synthetic records
// only (CrimeFixture, InventoryBaselineFixture).

import Foundation
@testable import OpenSkyCrime
import OpenSkyCrimeFixtures
@testable import OpenSkyCrimeInterface
@testable import OpenSkyCrimeTesting
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
import OpenSkyInventoryTesting
@testable import OpenSkyWorldState
import Testing

@MainActor
struct CrimeArrestTests {
    private typealias Items = InventoryBaselineFixture

    private let hold = CrimeFixture.key(CrimeFixture.Factions.hold)
    private let chestKey = CrimeFixture.key(CrimeFixture.Links.evidenceChest)

    private struct Session {
        let arrest: CrimeArrest
        let inventory: InventoryRuntime
        let crime: CrimeRuntime
        let evidence: InventoryHolder
    }

    private func session(bounty: Int32 = 40, gold: Int32 = 100) throws -> Session {
        let store = WorldStateStore()
        let crime = try CrimeFixture.runtime(store: store)
        let inventory = try InventoryRuntime(store: store, baselines: Items.resolver())
        crime.setCrimeGold(bounty, of: hold)
        if gold > 0 {
            try inventory.add(Items.gold, count: gold, to: .player)
        }
        let arrest = CrimeArrest(crime: crime, inventory: inventory)
        let evidence = try #require(arrest.unresidentEvidence(of: hold))
        return Session(arrest: arrest, inventory: inventory, crime: crime, evidence: evidence)
    }

    // MARK: - Links

    @Test func theFactionsJailLinksResolveToRuntimeIdentities() throws {
        let session = try session()
        #expect(session.arrest.evidenceChest(of: hold) == chestKey)
        #expect(
            session.arrest.releaseMarker(of: hold)
                == CrimeFixture.key(CrimeFixture.Links.jailMarker)
        )
        let tolerant = CrimeFixture.key(CrimeFixture.Factions.tolerant)
        #expect(session.arrest.evidenceChest(of: tolerant) == nil)
        #expect(session.evidence.key == chestKey)
        #expect(session.evidence.owner == .generated)
    }

    // MARK: - Paying

    @Test func canPayNeedsABountyAndTheGoldToCoverIt() throws {
        #expect(try session(bounty: 40, gold: 40).arrest.canPay(hold))
        #expect(try !session(bounty: 41, gold: 40).arrest.canPay(hold))
        #expect(try !session(bounty: 0, gold: 40).arrest.canPay(hold))
    }

    @Test func payingTakesTheGoldClearsTheBountyAndSeizesStolenGoods() throws {
        let session = try session(bounty: 40, gold: 100)
        try session.inventory.add(Items.lockpick, count: 2, to: .player, stolen: true)
        try session.inventory.add(Items.lockpick, count: 1, to: .player)

        let settlement = try session.arrest.pay(hold, evidence: session.evidence)

        #expect(settlement.goldPaid == 40)
        #expect(settlement.bounty == 40)
        #expect(settlement.sentenceDays == 0)
        #expect(settlement.releaseMarker == nil)
        #expect(settlement.evidenceChest == chestKey)
        #expect(settlement.confiscated == [
            InventoryStack(item: Items.lockpick, count: 2, stolen: true)
        ])
        #expect(session.inventory.goldCount(of: .player) == 60)
        #expect(session.inventory.count(of: Items.lockpick, in: .player) == 1)
        #expect(session.inventory.stolenCount(of: Items.lockpick, in: .player) == 0)
        #expect(session.inventory.stolenCount(of: Items.lockpick, in: session.evidence) == 2)
        #expect(session.crime.crimeGold(of: hold) == 0)
    }

    @Test func payingCanKeepTheGoodsAndGoToTheJailMarker() throws {
        let session = try session()
        try session.inventory.add(Items.lockpick, count: 2, to: .player, stolen: true)
        let settlement = try session.arrest.pay(
            hold, removeStolen: false, goToJail: true, evidence: session.evidence
        )
        #expect(settlement.confiscated.isEmpty)
        #expect(settlement.evidenceChest == nil)
        #expect(settlement.releaseMarker == CrimeFixture.key(CrimeFixture.Links.jailMarker))
        #expect(session.inventory.stolenCount(of: Items.lockpick, in: .player) == 2)
    }

    @Test func payingIsRefusedWithoutABountyOrWithoutTheGoldAndWritesNothing() throws {
        let poor = try session(bounty: 40, gold: 10)
        #expect(throws: ArrestRefusal.cannotAfford(owed: 40, gold: 10)) {
            try poor.arrest.pay(hold, evidence: poor.evidence)
        }
        #expect(poor.crime.crimeGold(of: hold) == 40)
        #expect(poor.inventory.goldCount(of: .player) == 10)

        let clean = try session(bounty: 0)
        #expect(throws: ArrestRefusal.noBounty) {
            try clean.arrest.pay(hold, evidence: clean.evidence)
        }
    }

    // MARK: - Jail

    @Test func jailClearsTheBountyKeepsTheGoldAndSeizesStolenGoods() throws {
        let session = try session(bounty: 250, gold: 100)
        try session.inventory.add(Items.sword, count: 1, to: .player, stolen: true)
        let settlement = try session.arrest.jail(hold, evidence: session.evidence)

        #expect(settlement.goldPaid == 0)
        #expect(settlement.sentenceDays == 2)
        #expect(settlement.releaseMarker == CrimeFixture.key(CrimeFixture.Links.jailMarker))
        #expect(session.inventory.goldCount(of: .player) == 100)
        #expect(session.inventory.count(of: Items.sword, in: .player) == 0)
        #expect(session.inventory.stolenCount(of: Items.sword, in: session.evidence) == 1)
        #expect(session.crime.crimeGold(of: hold) == 0)
    }

    @Test func noEvidenceChestLeavesTheStolenGoodsWithThePlayer() throws {
        let session = try session()
        try session.inventory.add(Items.sword, count: 1, to: .player, stolen: true)
        let settlement = try session.arrest.jail(hold, evidence: nil)
        #expect(settlement.confiscated.isEmpty)
        #expect(session.inventory.stolenCount(of: Items.sword, in: .player) == 1)
    }

    @Test func aSentenceIsADayPerHundredGoldBetweenOneAndSeven() {
        #expect(CrimeArrest.sentenceDays(bounty: 0) == 0)
        #expect(CrimeArrest.sentenceDays(bounty: 5) == 1)
        #expect(CrimeArrest.sentenceDays(bounty: 199) == 1)
        #expect(CrimeArrest.sentenceDays(bounty: 200) == 2)
        #expect(CrimeArrest.sentenceDays(bounty: 700) == 7)
        #expect(CrimeArrest.sentenceDays(bounty: 5000) == 7)
    }

    // MARK: - Confiscation arithmetic

    @Test func removingStolenUnequipsOnlyWhatLeftEntirely() {
        let state = ReferenceInventoryState(
            stacks: [
                InventoryStack(item: Items.sword, count: 1, stolen: true),
                InventoryStack(item: Items.helmet, count: 1, stolen: true),
                InventoryStack(item: Items.helmet, count: 1, stolen: false)
            ],
            equipped: [Items.sword, Items.helmet]
        )
        let (remaining, taken) = state.removingStolen()
        #expect(taken.count == 2)
        #expect(remaining.stacks == [InventoryStack(item: Items.helmet, count: 1)])
        #expect(remaining.equipped == [Items.helmet])
        #expect(ReferenceInventoryState().removingStolen().taken.isEmpty)
    }
}
