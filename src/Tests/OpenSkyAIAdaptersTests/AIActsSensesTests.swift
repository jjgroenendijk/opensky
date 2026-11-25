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
            .worlds
            .packageAction(.warn(Self.other, level: 1), actor: Self.actor) ==
            .lasts(seconds: 2))
        #expect(adapter.worlds.packageAction(.standDown, actor: Self.actor) == .done)
        #expect(graphs.raiseCalls.map(\.event) == ["WeapEquip", "Unequip"])
        #expect(host.fakeStoryWorld.sayTopicCalls.map(\.lookAt) == [Self.other])
    }

    /// With an NPC, DialogueActivate asks for a conversation and waits for an answer.
    @Test func talkingToAnNPCAsksForAConversation() {
        host.fakeActorWorld.combatActorsResult = [CombatActorObservation(
            key: Self.other,
            feet: .zero
        )]
        host.fakeStoryWorld.requestConversationResult = true
        let result = adapter.worlds.packageAction(.talk(to: Self.other), actor: Self.actor)
        #expect(result == .lasts(seconds: 20))
        #expect(host.fakeStoryWorld.requestConversationCalls.map(\.partner) == [Self.other])
    }

    @Test func talkingToAMissingNPCFails() {
        let result = adapter.worlds.packageAction(.talk(to: Self.other), actor: Self.actor)
        #expect(result == .failed)
        #expect(host.fakeStoryWorld.requestConversationCalls.isEmpty)
    }

    @Test func aForcedGreetingOpensTheDialogueMenu() {
        host.fakeDialogue.claimForceGreetResult = true
        host.fakeDialogueMenu.isOpen = true
        #expect(adapter.worlds.packageAction(.forceGreet(topic: nil), actor: Self.actor) == .done)
        #expect(host.fakeDialogueMenu.beginCalls == [Self.actor])
        host.fakeDialogue.claimForceGreetResult = false
        #expect(adapter.worlds.packageAction(.forceGreet(topic: nil), actor: Self.actor) == .failed)
    }

    /// A force-greet takes over the conversation of another speaker, and keeps its own.
    @Test(arguments: [false, true])
    func aForcedGreetingTakesOverAnotherConversation(ownConversation: Bool) {
        host.fakeDialogue.claimForceGreetResult = true
        host.fakeDialogueMenu.isOpen = true
        host.fakeDialogueMenu.speakerOrTarget = ownConversation ? Self.actor : Self.other
        _ = adapter.worlds.packageAction(.forceGreet(topic: nil), actor: Self.actor)
        #expect(host.fakeDialogueMenu.closeCallCount == (ownConversation ? 0 : 1))
    }

    @Test func withoutScriptsScriptedActsFail() {
        #expect(adapter.worlds.packageAction(.activate(Self.other), actor: Self.actor) == .failed)
        #expect(adapter.worlds.packageAction(.pickUp(Self.other), actor: Self.actor) == .failed)
        #expect(adapter.worlds
            .packageAction(.say(topic: nil, to: nil), actor: Self.actor) == .failed)
        #expect(adapter
            .worlds
            .packageAction(
                .attack(Self.other, startsCombat: true),
                actor: Self.actor
            ) ==
            .failed)
        #expect(adapter.worlds.packageAction(
            .setDoorsLocked(true, center: .zero, radius: 0),
            actor: Self.actor
        ) == .failed)
        adapter.worlds.stopPackageActor(Self.actor)
        #expect(host.fakeStreamer.actors.stopActorCalls == [Self.actor])
    }

    /// The player leads the targets, then each living NPC another NPC watches.
    @Test func anNPCFoeIsAPerceptionTargetAfterThePlayer() {
        let loop = FakeCombatLoopRuntimePort()
        loop.watchedPairs = [CombatFoePair(observer: Self.actor, target: Self.other)]
        host.fakeCombat.loop = loop
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: Self.actor, feet: .zero),
            CombatActorObservation(key: Self.other, feet: SIMD3(100, 0, 0), name: "Bandit")
        ]
        let session = FakeGameSessionPort()
        session.locomotion.status.gaitValue = ScriptPathWaits.gait(forSpeed: 0)
        session.locomotion.status.lastPlanValue = LocomotionStepPlan()
        host.gameSession = session
        let targets = adapter.perceptionWorlds.perceptionTargets()
        #expect(targets.map(\.key) == [.player, Self.other])
        #expect(targets.last?.traits.isInvisible == false)
        #expect(adapter.perceptionWorlds.perceptionActorPairs()
            == [DetectionPairKey(observer: Self.actor, target: Self.other)])
    }

    @Test func candidatesCarryHostilityFlightAndPackages() {
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: Self.actor, feet: .zero),
            CombatActorObservation(key: Self.other, feet: .zero, isDead: true)
        ]
        host.fakeFactions.hostilityResult = .hostile
        host.fakeDragonFlightWorld.isFlyingResult = true
        let candidates = adapter.perceptionWorlds.perceptionCandidates()
        #expect(candidates.map(\.isDead) == [false, true])
        let allHostile = candidates.allSatisfy(\.isHostile)
        let allFlying = candidates.allSatisfy(\.observer.isFlying)
        #expect(allHostile)
        #expect(allFlying)
        #expect(!candidates.contains { $0.hasPackage })
        #expect(adapter.perceptionWorlds.perceptionTargets().isEmpty)
        #expect(adapter.worlds.lightLevel(at: .zero) == 1)
    }

    /// A placement's heading is clockwise from north, so heading 0 looks along +Y.
    @Test func anObserverLooksAlongItsPlacementHeading() throws {
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: Self.actor, feet: .zero, heading: 0)
        ]
        host.fakeFactions.hostilityResult = .hostile
        host.fakeDragonFlightWorld.isFlyingResult = false
        let observer = try #require(adapter.perceptionWorlds.perceptionCandidates().first?.observer)
        #expect(abs(observer.heading.x) < 1e-5)
        #expect(abs(observer.heading.y - 1) < 1e-5)
    }

    /// A running Ambush package gives the observer the area it waits on.
    @Test func anAmbushPackageGivesTheObserverItsArea() throws {
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: Self.actor, feet: .zero, heading: 0)
        ]
        host.fakeFactions.hostilityResult = .hostile
        host.fakeDragonFlightWorld.isFlyingResult = false
        for (area, expected) in [
            (PackageAmbushArea.everyone, DetectionAmbushArea.everyone),
            (
                .within(center: SIMD3(1, 2, 3), radius: 40),
                .within(center: SIMD3(1, 2, 3), radius: 40)
            ),
            (.unmatched, .unmatched)
        ] {
            host.fakePackages.ambushAreaResult = area
            let observer = try #require(
                adapter.perceptionWorlds.perceptionCandidates().first?.observer
            )
            #expect(observer.ambush == expected)
        }
    }

    /// Only the actors `isDue` asks for are built; the rest are listed by key.
    @Test func aRefreshBuildsOnlyTheDueActors() {
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: Self.actor, feet: .zero),
            CombatActorObservation(key: Self.other, feet: SIMD3(9000, 0, 0))
        ]
        host.fakeFactions.hostilityResult = .hostile
        host.fakeDragonFlightWorld.isFlyingResult = false
        let refresh = adapter.perceptionWorlds.perceptionCandidates { key, _ in key == Self.actor }
        #expect(refresh.present == [Self.actor, Self.other])
        #expect(refresh.fresh.map(\.observer.key) == [Self.actor])
        let none = adapter.perceptionWorlds.perceptionCandidates { _, _ in false }
        #expect(none.present == [Self.actor, Self.other])
        #expect(none.fresh.isEmpty)
    }

    @Test func sightIsBlockedOnlyByStaticCollision() {
        #expect(adapter.worlds.perceptionHasLineOfSight(from: .zero, to: .zero))
        #expect(adapter.perceptionWorlds.perceptionHasLineOfSight(from: .zero, to: .zero))
        host.fakeStreamer.collision.staticCollisionBlocksResult = true
        #expect(!adapter.worlds.perceptionHasLineOfSight(from: .zero, to: SIMD3(0, 100, 0)))
        #expect(host.fakeStreamer.collision.staticCollisionBlocksCalls.count == 1)
    }

    @Test func sneakingAgainstObserversIsASkillUse() {
        adapter.perceptionSense.run([.reportSneakSkillUse(2, by: .player)])
        #expect(host.fakeProgression.reportSkillUseCalls.map(\.amount) == [2])
    }

    @Test func seatsAreReservedAndReleasedThroughTheFurniturePort() {
        host.fakeFurniture.isInUseResult = true
        #expect(adapter.worlds.packageSeat(in: Self.other, actor: Self.actor, animation: 1) == nil)
        adapter.worlds.unseatPackageActor(Self.actor, from: nil)
        #expect(adapter.worlds.isFurnitureInUse(Self.other, marker: nil, ignoringReserved: true))
        adapter.worlds.setSittingRotation(degrees: 90)
        adapter.furnitureWorlds.playerAskedToStand()
        #expect(host.fakeFurniture.reserveCalls.count == 1)
        #expect(host.fakeFurniture.releaseReservationsCalls == [Self.actor])
        #expect(host.fakeFurniture.setSittingRotationCalls == [90])
        #expect(host.fakeVehicleWorld.setSittingRotationCalls == [90])
        #expect(host.fakeFurniture.standCalls == [.player])
    }

    @Test func unknownFurnitureHasNoSeatsOrStation() {
        #expect(adapter.worlds.furnitureSeats(of: Self.other) == nil)
        #expect(adapter.furnitureWorlds.furnitureSeats(of: Self.other) == nil)
        #expect(!adapter.furnitureWorlds.furnitureIsSpecial(Self.other))
        #expect(!adapter.furnitureWorlds.furnitureActorHasKeyword(Self.actor, FormID(0x50)))
        #expect(adapter.furnitureWorlds.residentFurniture().isEmpty)
        #expect(adapter.furnitureWorlds.furnitureMotion(of: Self.actor) == nil)
        #expect(!adapter.furnitureWorlds.furnitureExitIsLoading(Self.actor))
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
        #expect(adapter.packageActs.references.shoutSpell(of: Self.other) == nil)
        #expect(adapter.packageActs.references.shoutSpell(for: nil) == nil)
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
