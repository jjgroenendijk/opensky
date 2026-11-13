// The lock and refused-activation adapters gather their facts from the session ports.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
@testable import OpenSkyInventoryAdapters
import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct LockAndRefusalAdapterTests {
    private let host = InventoryHost()
    private static let key = InventoryAdapterFixture.key

    @Test func lockFactsComeFromTheirPorts() {
        let locks = LockWorldAdapter(game: host, stage: nil)
        let locked = InventoryAdapterFixture.interaction(
            .open, lock: LockData(level: .novice, key: nil)
        )
        host.fakePerks.modifiedValueAtOnLockResult = 2
        host.fakePerks.modifiedValueAtOnGivenResult = 1
        host.fakeProgression.reportSkillUseResult = 5
        host.fakeCrime.reportLockpickingResult = 10
        host.fakeInventory.nameResult = "Lockpick"
        host.fakeStreamer.residents.residentInteractions = [
            locked,
            InventoryAdapterFixture.interaction(.take)
        ]
        #expect(locks.lockpickingSkill == 0)
        #expect(locks.playerLevel == 1)
        #expect(locks.perkValue(1, at: .modLockpickSweetSpot, lock: Self.key, level: 25) == 2)
        #expect(locks.activationFilter(of: Self.key) == 1)
        let use = SkillUseEvent(actor: .player, action: .lockpick, amount: 1)
        #expect(locks.reportSkillUse(use) == 5)
        #expect(locks.reportLockpickingCrime(on: Self.key) == 10)
        locks.countLockPicked()
        #expect(locks.lockables() == [locked])
        #expect(locks.itemName(FormID(0xA)) == "Lockpick")
        #expect(host.fakeWorldState.incrementMiscStatCalls.map(\.name) == ["Locks Picked"])
        #expect(host.fakePerks.modifiedValueAtOnLockCalls.map(\.lock.level) == [25])
    }

    @Test func eachFrameStepsTheLockpickingBoard() {
        LockWorldAdapter(game: host).stepLockpicking()
        #expect(host.fakeLockpickingMenu.tickCallCount == 1)
    }

    @Test func anUnplacedTargetHasOnlyItsOwnFacts() {
        let refusal = ActivationRefusalWorldAdapter(game: host, stage: nil)
        let bed = InventoryAdapterFixture.interaction(.use)
        host.fakeActorWorld.isInCombatResult = true
        let facts = refusal.facts(for: InventoryAdapterFixture.target(bed))
        #expect(facts.action == .use)
        #expect(!facts.isFurniture)
        #expect(facts.actor == nil)
        #expect(!facts.playerIsChild)
    }

    @Test func aTalkTargetGathersTheActorState() throws {
        let refusal = ActivationRefusalWorldAdapter(game: host, stage: nil)
        host.fakeStreamer.referenceEntryFormIDResult = try InventoryAdapterFixture.actorEntry()
        host.fakeRagdollWorld.holderResult = .player
        host.fakeMagic.archetypeActions.influenceResult = ActorMagicInfluence(isCalmed: true)
        host.fakeScenes.actorsInScenesResult = [Self.key]
        let talk = InventoryAdapterFixture.target(InventoryAdapterFixture.interaction(.talk))
        let actor = try #require(refusal.facts(for: talk).actor)
        #expect(actor.name == "Thing")
        #expect(actor.isCreature)
        #expect(actor.isCalmed)
        #expect(!actor.isFleeing)
        #expect(!actor.isUnconscious)
        #expect(actor.isInScene)
    }

    @Test func aChairHeldByAnotherActorIsReserved() throws {
        let refusal = ActivationRefusalWorldAdapter(game: host, stage: nil)
        let ledger = FakeFurnitureSeatLedgerPort()
        ledger.holdersResult = [0: .generated(9)]
        host.fakeFurniture.ledger = ledger
        host.fakeStreamer.referenceEntryFormIDResult = try InventoryAdapterFixture.referenceEntry()
        let chair = InventoryAdapterFixture.interaction(
            .activate, seats: [InventoryAdapterFixture.seat()]
        )
        let facts = refusal.facts(for: InventoryAdapterFixture.target(chair))
        #expect(facts.isFurniture)
        #expect(facts.furnitureReserved)
        #expect(!facts.furnitureOccupied)
    }
}
