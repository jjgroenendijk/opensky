// The navigation, package move, and package state parts move, place, and read package actors.

import OpenSkyActorsInterface
import OpenSkyAIAdapters
import OpenSkyAIPackages
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyRenderCore
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct AIPackageMovesStateTests {
    private let host = AIHost()
    private let adapter: AIWorldAdapter
    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)

    init() {
        adapter = AIWorldAdapter(game: host, stage: nil)
    }

    @Test func navigationForwardsMovesAndHostility() {
        host.fakeStreamer.moveActorResult = .started
        host.fakeStreamer.stopActorResult = true
        host.fakeFactions.hostilityResult = .hostile
        #expect(adapter.moveActor(Self.actor, to: .zero) == .started)
        #expect(adapter.stopActor(Self.actor))
        #expect(adapter.isHostile(Self.actor))
        adapter.setHostile(false, actor: Self.actor)
        #expect(host.fakeFactions.setHostilityCalls.map(\.hostility) == [.neutral])
        #expect(adapter.camera == nil)
        #expect(adapter.animationClips == nil)
    }

    @Test func actorCandidatesComeFromTheActorWorld() {
        host.fakeActorWorld.combatActorsResult = [CombatActorObservation(
            key: Self.actor,
            feet: .one
        )]
        #expect(adapter.actorCandidates().map(\.key) == [Self.actor])
        #expect(adapter.actorCandidates().map(\.feet) == [.one])
    }

    @Test func aRiderWithoutAHorseLinkStaysOnFoot() {
        #expect(adapter.mountPackageActor(Self.actor) == nil)
        adapter.dismountPackageActor(Self.actor)
        #expect(host.fakeVehicleWorld.detachCalls == [Self.actor])
        #expect(host.fakeNpcAnimation.dismountCalls == [Self.actor])
        #expect(host.fakeStreamer.stopActorCalls.isEmpty)
    }

    @Test func aLiveTransformPlacesTheActor() {
        host.fakeStreamer.npcTransformResult = ReferenceTransformOverride(position: .one)
        #expect(adapter.packageActorPosition(Self.actor) == .one)
        #expect(adapter.packageActorPosition(.player) == nil)
        #expect(adapter.furnitureActorPosition(Self.actor) == .one)
    }

    @Test func onlyAnExteriorPackageActorFlies() {
        host.fakeDragonFlightWorld.actorFliesPackagesResult = true
        #expect(adapter.packageActorFlies(Self.actor))
        #expect(!adapter.packageActorFlies(.player))
        host.fakeVehicleWorld.isPlayerAIDriven = true
        #expect(adapter.packageDrivesPlayer)
    }

    @Test func sandboxEndsReleaseTheirMarkers() throws {
        let idles = try #require(host.fakeIdleWorld.idles as? FakeIdlePort)
        idles.holdsMarkerResult = true
        #expect(adapter.packageActorHoldsIdleMarker(Self.actor))
        adapter.packageSandboxActivityEnded(.idleMarker, actor: Self.actor)
        adapter.packageSandboxActivityEnded(.wandering, actor: Self.actor)
        #expect(idles.leaveMarkerCalls.count == 1)
        #expect(idles.allowPreviousMarkerCalls == [Self.actor])
    }

    @Test func aMoveIsRecordedAndMapped() {
        host.fakeStreamer.moveActorResult = .started
        #expect(adapter.movePackageActor(
            Self.actor,
            to: .one,
            direct: false,
            gait: nil,
            walkRunBlend: nil
        ) == .started)
        host.fakeStreamer.moveActorResult = .moverCapReached
        #expect(adapter.movePackageActor(
            Self.actor,
            to: .one,
            direct: true,
            gait: nil,
            walkRunBlend: nil
        ) == .busy)
        #expect(host.fakePackages.recordMoveCalls.map(\.actor) == [Self.actor, Self.actor])
        host.fakeFurniture.isLeavingSeatResult = true
        #expect(adapter.movePackageActor(
            Self.actor,
            to: .one,
            direct: true,
            gait: nil,
            walkRunBlend: nil
        ) == .busy)
        #expect(adapter.movePackageActor(
            .player,
            to: .one,
            direct: true,
            gait: nil,
            walkRunBlend: nil
        ) == .failed)
    }

    @Test func withoutScriptsOrSessionPackageReadsAreEmpty() {
        #expect(adapter.packageAliasStacks().isEmpty)
        #expect(adapter.packageClock == nil)
        #expect(adapter.packageResidents() == nil)
        #expect(adapter.packageActorGait(.player) == nil)
        #expect(adapter.packageLeveledRoll(of: Self.actor, base: FormID(0x40)) == nil)
        #expect(!adapter.isAIDisabled(Self.actor))
        #expect(adapter.packageData() == nil)
    }

    @Test func activityReadsDeathFirst() {
        #expect(adapter.packageActorActivity(Self.actor) == .free)
        host.fakeWorldState.componentResult = ActorDeathState(isDead: true)
        #expect(adapter.packageActorActivity(Self.actor) == .dead)
    }

    @Test func theMoverAlwaysHasRoomForThePlayer() {
        let movement = host.fakeStreamer.npcMovement
        movement.hasRoomResult = false
        #expect(adapter.packageMoverHasRoom(for: .player))
        #expect(!adapter.packageMoverHasRoom(for: Self.actor))
    }
}

@MainActor
struct AISessionReadsTests {
    private let host = AIHost()

    @Test func theCameraComesFromTheSession() {
        let session = FakeGameSessionPort()
        session.freeFlyCameraValue = FreeFlyCamera(position: [1, 2, 3], yaw: 0, pitch: 0)
        host.gameSession = session
        let adapter = AIWorldAdapter(game: host, stage: nil)
        #expect(adapter.camera?.position == [1, 2, 3])
    }
}
