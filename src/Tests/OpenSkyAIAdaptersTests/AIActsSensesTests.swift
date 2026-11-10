// The package acts, senses, and seating parts act for package actors and read what they sense.

import OpenSkyActorsInterface
import OpenSkyAIAdapters
import OpenSkyAIPackages
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyProgressionInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import Testing

@MainActor
struct AIActsSensesTests {
    private let host = AIHost()
    private let adapter: AIWorldAdapter
    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let other = ReferenceKey.plugin(name: "base.esm", objectID: 0x21)

    init() {
        adapter = AIWorldAdapter(game: host, stage: nil)
    }

    @Test func aGuardDrawsAndWarnsThenStandsDown() throws {
        let graphs = try #require(host.fakeActorGraphWorld.graphs as? FakeActorGraphPort)
        host.fakeStoryWorld.sayTopicResult = 2
        #expect(adapter
            .packageAction(.warn(Self.other, level: 1), actor: Self.actor) == .lasts(seconds: 2))
        #expect(adapter.packageAction(.standDown, actor: Self.actor) == .done)
        #expect(graphs.raiseCalls.map(\.event) == ["WeapEquip", "Unequip"])
        #expect(host.fakeStoryWorld.sayTopicCalls.map(\.lookAt) == [Self.other])
    }

    @Test func talkingLooksAtTheTarget() {
        let result = adapter.packageAction(.talk(to: Self.other), actor: Self.actor)
        #expect(result == .lasts(seconds: PackageActionResult.lookSeconds))
        #expect(host.fakeHeadTracking.setLookTargetCalls.count == 1)
    }

    @Test func aForcedGreetingOpensTheDialogueMenu() {
        host.fakeDialogue.claimForceGreetResult = true
        host.fakeDialogueMenu.isOpen = true
        #expect(adapter.packageAction(.forceGreet(topic: nil), actor: Self.actor) == .done)
        #expect(host.fakeDialogueMenu.beginCalls == [Self.actor])
        host.fakeDialogue.claimForceGreetResult = false
        #expect(adapter.packageAction(.forceGreet(topic: nil), actor: Self.actor) == .failed)
    }

    @Test func withoutScriptsScriptedActsFail() {
        #expect(adapter.packageAction(.activate(Self.other), actor: Self.actor) == .failed)
        #expect(adapter.packageAction(.pickUp(Self.other), actor: Self.actor) == .failed)
        #expect(adapter.packageAction(.say(topic: nil, to: nil), actor: Self.actor) == .failed)
        #expect(adapter
            .packageAction(.attack(Self.other, startsCombat: true), actor: Self.actor) == .failed)
        #expect(adapter.packageAction(
            .setDoorsLocked(true, center: .zero, radius: 0),
            actor: Self.actor
        ) == .failed)
        adapter.stopPackageActor(Self.actor)
        #expect(host.fakeStreamer.stopActorCalls == [Self.actor])
    }

    @Test func candidatesCarryHostilityFlightAndPackages() {
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: Self.actor, feet: .zero),
            CombatActorObservation(key: Self.other, feet: .zero, isDead: true)
        ]
        host.fakeFactions.hostilityResult = .hostile
        host.fakeDragonFlightWorld.isFlyingResult = true
        let candidates = adapter.perceptionCandidates()
        #expect(candidates.map(\.isDead) == [false, true])
        let allHostile = candidates.allSatisfy(\.isHostile)
        let allFlying = candidates.allSatisfy(\.observer.isFlying)
        #expect(allHostile)
        #expect(allFlying)
        #expect(!candidates.contains { $0.hasPackage })
        #expect(adapter.perceptionTargets().isEmpty)
        #expect(adapter.lightLevel(at: .zero) == 1)
    }

    @Test func sightIsBlockedOnlyByStaticCollision() {
        #expect(adapter.perceptionHasLineOfSight(from: .zero, to: .zero))
        host.fakeStreamer.staticCollisionBlocksResult = true
        #expect(!adapter.perceptionHasLineOfSight(from: .zero, to: SIMD3(0, 100, 0)))
        #expect(host.fakeStreamer.staticCollisionBlocksCalls.count == 1)
    }

    @Test func sneakingAgainstObserversIsASkillUse() {
        adapter.perceptionSense.run([.reportSneakSkillUse(2, by: .player)])
        #expect(host.fakeProgression.reportSkillUseCalls.map(\.amount) == [2])
    }

    @Test func seatsAreReservedAndReleasedThroughTheFurniturePort() {
        host.fakeFurniture.isInUseResult = true
        #expect(adapter.packageSeat(in: Self.other, actor: Self.actor, animation: 1) == nil)
        adapter.unseatPackageActor(Self.actor, from: nil)
        #expect(adapter.isFurnitureInUse(Self.other, marker: nil, ignoringReserved: true))
        adapter.setSittingRotation(degrees: 90)
        adapter.playerAskedToStand()
        #expect(host.fakeFurniture.reserveCalls.count == 1)
        #expect(host.fakeFurniture.releaseReservationsCalls == [Self.actor])
        #expect(host.fakeFurniture.setSittingRotationCalls == [90])
        #expect(host.fakeVehicleWorld.setSittingRotationCalls == [90])
        #expect(host.fakeFurniture.standCalls == [.player])
    }

    @Test func unknownFurnitureHasNoSeatsOrStation() {
        #expect(adapter.furnitureSeats(of: Self.other) == nil)
        #expect(!adapter.furnitureIsSpecial(Self.other))
        #expect(!adapter.furnitureActorHasKeyword(Self.actor, FormID(0x50)))
        #expect(adapter.residentFurniture().isEmpty)
        #expect(adapter.furnitureMotion(of: Self.actor) == nil)
        #expect(!adapter.furnitureExitIsLoading(Self.actor))
    }

    @Test func standingActorsSkipTheDeadAndTheRiders() {
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: Self.actor, feet: .one),
            CombatActorObservation(key: Self.other, feet: .zero, isDead: true)
        ]
        adapter.bumps.advanceBumps()
        #expect(adapter.bumps.standingActors().map(\.key) == [Self.actor])
    }

    @Test func withoutRecordsNoShoutSpellBoundsOrSpeeds() throws {
        let graphs = try #require(host.fakeActorGraphWorld.graphs as? FakeActorGraphPort)
        graphs.movementStateNameResult = "NPC_Walk_MT"
        #expect(adapter.packageActs.shoutSpell(of: Self.other) == nil)
        #expect(adapter.packageActs.shoutSpell(for: nil) == nil)
        #expect(adapter.bodyBoundsLoader() == nil)
        #expect(adapter.movementSpeeds(of: Self.actor) == nil)
        #expect(graphs.movementStateNameCalls == [Self.actor])
    }

    @Test func withScriptFilesBodyBoundsLoadAndAnUnknownGaitHasNoSpeeds() throws {
        host.aiRecords = FakeAIRecords()
        #expect(adapter.bodyBoundsLoader() != nil)
        #expect(adapter.movementSpeeds(of: Self.actor) == nil)
        let graphs = try #require(host.fakeActorGraphWorld.graphs as? FakeActorGraphPort)
        graphs.movementStateNameResult = "NPC_Walk_MT"
        #expect(adapter.movementSpeeds(of: Self.actor) == nil)
    }
}
