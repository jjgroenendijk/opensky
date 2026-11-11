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
        #expect(adapter.worlds.moveActor(Self.actor, to: .zero) == .started)
        #expect(adapter.worlds.stopActor(Self.actor))
        #expect(adapter.worlds.isHostile(Self.actor))
        adapter.worlds.setHostile(false, actor: Self.actor)
        #expect(host.fakeFactions.setHostilityCalls.map(\.hostility) == [.neutral])
        #expect(adapter.worlds.camera == nil)
        #expect(adapter.worlds.animationClips == nil)
    }

    @Test func actorCandidatesComeFromTheActorWorld() {
        host.fakeActorWorld.combatActorsResult = [CombatActorObservation(
            key: Self.actor,
            feet: .one
        )]
        #expect(adapter.worlds.actorCandidates().map(\.key) == [Self.actor])
        #expect(adapter.worlds.actorCandidates().map(\.feet) == [.one])
    }

    @Test func aRiderWithoutAHorseLinkStaysOnFoot() {
        #expect(adapter.worlds.mountPackageActor(Self.actor) == nil)
        adapter.worlds.dismountPackageActor(Self.actor)
        #expect(host.fakeVehicleWorld.detachCalls == [Self.actor])
        #expect(host.fakeNpcAnimation.dismountCalls == [Self.actor])
        #expect(host.fakeStreamer.stopActorCalls.isEmpty)
    }

    @Test func aLiveTransformPlacesTheActor() {
        host.fakeStreamer.npcTransformResult = ReferenceTransformOverride(position: .one)
        #expect(adapter.worlds.packageActorPosition(Self.actor) == .one)
        #expect(adapter.worlds.packageActorPosition(.player) == nil)
        #expect(adapter.worlds.furnitureActorPosition(Self.actor) == .one)
    }

    @Test func onlyAnExteriorPackageActorFlies() {
        host.fakeDragonFlightWorld.actorFliesPackagesResult = true
        #expect(adapter.worlds.packageActorFlies(Self.actor))
        #expect(!adapter.worlds.packageActorFlies(.player))
        host.fakeVehicleWorld.isPlayerAIDriven = true
        #expect(adapter.worlds.packageDrivesPlayer)
    }

    @Test func sandboxEndsReleaseTheirMarkers() throws {
        let idles = try #require(host.fakeIdleWorld.idles as? FakeIdlePort)
        idles.holdsMarkerResult = true
        #expect(adapter.worlds.packageActorHoldsIdleMarker(Self.actor))
        adapter.worlds.packageSandboxActivityEnded(.idleMarker, actor: Self.actor)
        adapter.worlds.packageSandboxActivityEnded(.wandering, actor: Self.actor)
        #expect(idles.leaveMarkerCalls.count == 1)
        #expect(idles.allowPreviousMarkerCalls == [Self.actor])
    }

    @Test func aMoveIsRecordedAndMapped() {
        host.fakeStreamer.moveActorResult = .started
        #expect(adapter
            .worlds.movePackageActor(PackageMove(Self.actor, to: .one, direct: false)) == .started)
        host.fakeStreamer.moveActorResult = .moverCapReached
        #expect(adapter.worlds
            .movePackageActor(PackageMove(Self.actor, to: .one, direct: true)) == .busy)
        #expect(host.fakePackages.recordMoveCalls.map(\.actor) == [Self.actor, Self.actor])
        host.fakeFurniture.isLeavingSeatResult = true
        #expect(adapter.worlds
            .movePackageActor(PackageMove(Self.actor, to: .one, direct: true)) == .busy)
        #expect(adapter.worlds
            .movePackageActor(PackageMove(.player, to: .one, direct: true)) == .failed)
    }

    @Test func withoutScriptsOrSessionPackageReadsAreEmpty() {
        #expect(adapter.worlds.packageAliasStacks().isEmpty)
        #expect(adapter.worlds.packageClock == nil)
        #expect(adapter.worlds.packageResidents() == nil)
        #expect(adapter.worlds.packageActorGait(.player) == nil)
        #expect(adapter.worlds.packageLeveledRoll(of: Self.actor, base: FormID(0x40)) == nil)
        #expect(!adapter.worlds.isAIDisabled(Self.actor))
        #expect(adapter.packageData() == nil)
    }

    @Test func activityReadsDeathFirst() {
        #expect(adapter.worlds.packageActorActivity(Self.actor) == .free)
        host.fakeWorldState.componentResult = ActorDeathState(isDead: true)
        #expect(adapter.worlds.packageActorActivity(Self.actor) == .dead)
    }

    @Test func theMoverAlwaysHasRoomForThePlayer() {
        let movement = host.fakeStreamer.npcMovement
        movement.hasRoomResult = false
        #expect(adapter.worlds.packageMoverHasRoom(for: .player))
        #expect(!adapter.worlds.packageMoverHasRoom(for: Self.actor))
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
        #expect(adapter.worlds.camera?.position == [1, 2, 3])
    }
}
