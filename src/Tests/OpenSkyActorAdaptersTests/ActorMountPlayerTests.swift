// The actor, dragon flight, mount, player, and vehicle worlds read and drive their ports.

import OpenSkyActorAdapters
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkySessionTesting
import OpenSkyWorldInterface
import Testing

@MainActor
struct ActorMountPlayerTests {
    private let host = ActorHost()
    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)

    @Test func withoutALoopNoActorIsInCombat() {
        let actors = ActorWorldAdapter(game: host, stage: nil)
        #expect(!actors.isInCombat(Self.actor))
        #expect(!actors.isCasting(Self.actor))
        #expect(actors.combatActor(key: Self.actor) == nil)
        #expect(actors.riddenHorse() == nil)
        actors.setRiddenHorseSprintAllowed(true)
        #expect(!actors.isRiddenHorseSprinting())
        #expect(actors.playerCarriedWeight() == nil)
        #expect(host.fakeStreamer.residentActorEntryCalls == [Self.actor])
    }

    @Test func flightForwardsToStreamerGraphsAndPackages() {
        let flight = DragonFlightWorldAdapter(game: host, stage: nil)
        flight.flightReachedPackageTarget(Self.actor)
        flight.releaseFromFlight(Self.actor)
        flight.raiseFlightEvent("TakeOff", on: Self.actor)
        #expect(host.fakePackages.flightArrivedCalls == [Self.actor])
        #expect(host.fakeStreamer.releaseRiddenActorCalls == [Self.actor])
        #expect(host.fakeActorGraphs.raiseCalls.map(\.event) == ["TakeOff"])
        #expect(flight.holdForFlight(Self.actor) == nil)
        #expect(flight.flightGroundHeight(at: .zero) == nil)
        #expect(!flight.isFlying(Self.actor))
    }

    @Test func onlyAnAllowedFlierFliesPackages() {
        let flight = DragonFlightWorldAdapter(game: host, stage: nil)
        host.fakeCombatWorld.actorFliesResult = true
        #expect(flight.actorFliesPackages(Self.actor))
        host.fakeCombatWorld.actorFliesResult = false
        #expect(!flight.actorFliesPackages(Self.actor))
    }

    @Test func anInactiveMountIgnoresActivation() {
        let mounts = MountWorldAdapter(game: host, stage: nil)
        #expect(!mounts.takeActivation())
        #expect(!mounts.isMountActive)
        #expect(mounts.flyingMounts.isEmpty)
        #expect(mounts.mountKind == nil)
        #expect(mounts.lockCandidate() == nil)
        #expect(mounts.switchCandidates().isEmpty)
        #expect(mounts.allowsFlyingMountLandingRequests())
    }

    @Test func onlyALivingActorHasFeet() {
        let mounts = MountWorldAdapter(game: host, stage: nil)
        host.fakeActorWorld.combatActorResult = CombatActorObservation(key: Self.actor, feet: .one)
        #expect(mounts.livingActorFeet(Self.actor) == .one)
        host.fakeActorWorld.combatActorResult = CombatActorObservation(
            key: Self.actor,
            feet: .one,
            isDead: true
        )
        #expect(mounts.livingActorFeet(Self.actor) == nil)
    }

    @Test func withoutASessionThePlayerReadsHaveDefaults() {
        let player = PlayerWorldAdapter(game: host, stage: nil)
        host.fakeCombat.isWeaponDrawn = true
        #expect(player.playerWeaponsDrawn)
        #expect(player.isPlayerGrounded)
        #expect(player.firstPersonFOVYRadians == nil)
        #expect(player.firstPersonArmsEnabled == nil)
        #expect(!player.areFirstPersonArmsVisible)
        #expect(player.faceMorphSubject == nil)
        #expect(player.faceMorphPlaybacks.isEmpty)
        #expect(player.rigSource() == nil)
        #expect(player.playerLocomotion == nil)
    }

    @Test func vehicleCallsReachIdlesPackagesAndTheStreamer() {
        let vehicles = VehicleWorldAdapter(game: host, stage: nil)
        vehicles.evaluatePackage(Self.actor)
        #expect(host.fakePackages.evaluateCalls == [Self.actor])
        #expect(vehicles.vehicleFormID(of: Self.actor) == nil)
        #expect(!vehicles.vehicleHasBone(Self.actor, named: "SaddleBone"))
        #expect(!vehicles.isInKillMove(Self.actor))
        vehicles.setPlayerAIDriven(true)
        #expect(vehicles.isPlayerAIDriven)
    }

    @Test func aBoneIsFoundOnTheActorsPlayback() {
        let playback = FakeActorAnimationPlaybackPort()
        playback.hasBoneResult = true
        host.playbacks[Self.actor] = playback
        let vehicles = VehicleWorldAdapter(game: host, stage: nil)
        #expect(vehicles.vehicleHasBone(Self.actor, named: "SaddleBone"))
        #expect(playback.hasBoneCalls == ["SaddleBone"])
    }

    @Test func aSprintingPlayerCarriesTheEquippedLoad() {
        let actors = ActorWorldAdapter(game: host, stage: nil)
        let session = FakeGameSessionPort()
        session.locomotion.status.gaitValue = .sprint
        session.locomotion.status.horizontalVelocity = SIMD2(2, 0)
        host.gameSession = session
        #expect(actors.playerSprintLoad() == 0)
        session.locomotion.status.gaitValue = .walk
        #expect(actors.playerSprintLoad() == nil)
        actors.setPlayerSprintAllowed(true)
        #expect(session.locomotion.isSprintAllowed)
    }

    @Test func anOverencumberedPlayerCannotRunAndIsTold() {
        let actors = ActorWorldAdapter(game: host, stage: nil)
        let session = FakeGameSessionPort()
        host.gameSession = session
        actors.setPlayerOverencumbered(false)
        #expect(session.locomotion.isRunAllowed)
        #expect(host.fakeHud.showNotificationCalls.isEmpty)
        actors.setPlayerOverencumbered(true)
        #expect(!session.locomotion.isRunAllowed)
        #expect(host.fakeHud.showNotificationCalls == [
            "You are carrying too much to be able to run."
        ])
    }

    @Test func withoutActorRecordsAnActorHasNoName() {
        let actors = ActorWorldAdapter(game: host, stage: nil)
        #expect(actors.displayName(of: Self.actor, base: FormID(0x20)) == nil)
        #expect(actors.displayName(of: Self.actor, base: FormID(0x20)) == nil)
    }
}
