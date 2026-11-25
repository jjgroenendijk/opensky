// The part types the actor adapters hand their jobs to: without a session or records,
// each answers its empty default and drives no port.

@testable import OpenSkyActorAdapters
import OpenSkyActorPresentation
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkySessionInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd
import Testing

@MainActor
struct ActorAdapterPartsTests {
    private let host = ActorHost()
    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)

    @Test func leavingEveryVehicleFreesTheRidingPlayer() {
        let session = FakeGameSessionPort()
        session.playerSeat = matrix_identity_float4x4
        session.playerWalkPath = [SIMD3(1, 2, 3)]
        host.gameSession = session
        let vehicles = VehicleWorldAdapter(game: host, stage: nil)
        vehicles.setPlayerAIDriven(true)
        vehicles.ridesPlayer = true
        vehicles.leaveAllVehicles()
        #expect(!vehicles.isPlayerAIDriven)
        #expect(!vehicles.ridesPlayer)
        #expect(session.playerSeat == nil)
        #expect(session.playerWalkPath.isEmpty)
        #expect(host.fakeHud.setCartModeCalls == [false])
        // A chair, not a ride, holds this seat, so it stays.
        session.playerSeat = matrix_identity_float4x4
        vehicles.leaveAllVehicles()
        #expect(session.playerSeat != nil)
    }

    @Test func withoutASessionTheSeatViewTurnsNothing() {
        let vehicles = VehicleWorldAdapter(game: host, stage: nil)
        vehicles.placePlayer(at: ReferenceTransformOverride(position: .zero))
        vehicles.setSittingRotation(degrees: 30)
        #expect((host.fakeIdleWorld.idles as? FakeIdlePort)?.idleBoneCalls.isEmpty == true)
    }

    @Test func aFollowerStayingInItsCellWritesNoState() {
        let vehicles = VehicleWorldAdapter(game: host, stage: nil)
        host.fakeStreamer.cellLocationResult = .exterior(CellCoordinate(x: 0, y: 0))
        vehicles.vehicleFollowerMoved(
            Self.actor, to: ReferenceTransformOverride(position: SIMD3(5000, 10, 0))
        )
        #expect(host.fakeStreamer.requestRebuildCalls.isEmpty)
    }

    @Test func withoutALoaderAVehicleHasNoWheels() {
        let vehicles = VehicleWorldAdapter(game: host, stage: nil)
        #expect(vehicles.vehicleWheels(of: Self.actor)?.isEmpty == true)
    }

    /// A rider's exit travel comes from the idle's root motion, held inside the clip.
    @Test func aRiderTravelReadsTheIdleRootMotion() {
        let vehicles = VehicleWorldAdapter(game: host, stage: nil)
        let idles = FakeIdlePort()
        host.fakeIdleWorld.idles = idles
        #expect(vehicles.vehicleRiderTravel(of: Self.actor) == nil)
        idles.rootMotionResult = (
            AnimationRootMotion(duration: 2, translations: [], rotations: []), elapsed: 5
        )
        let travel = vehicles.vehicleRiderTravel(of: Self.actor)
        #expect(travel?.offset == .zero)
        #expect(travel?.yaw == 0)
    }

    @Test func aWorldStepTicksTheControllersWithoutTraps() {
        let objects = ObjectAnimationWorldAdapter(game: host, stage: nil)
        objects.advance(0.5)
        #expect(host.fakeNodeControllers.tickCalls == [0.5])
    }

    @Test func withoutASessionNoMetersArePublished() {
        let actors = ActorWorldAdapter(game: host, stage: nil)
        actors.hudMeters.publishHUDMeters(gameSession: nil)
        #expect(host.fakeHud.publishMetersCalls.isEmpty)
    }

    @Test func theDoorGateRegistersItsCheckAndItsRefusal() {
        let seam = FakeActivationGateSeamPort()
        seam.refusals = FrameSchedule()
        host.fakeStreamer.activationGate = seam
        let mounts = MountWorldAdapter(game: host, stage: nil)
        mounts.doorGate.registerDoorGate()
        #expect(seam.registerCalls == [.mount])
        host.fakeMounts.settings = .vanilla
        let door = PlacedInteraction(
            reference: FormID(0x500), base: FormID(0x300), position: .zero, name: "Door",
            action: .open, actionLabel: "Open", sounds: nil, voiceType: nil
        )
        let target = InteractionTarget(interaction: door, hitPosition: .zero, distance: 1)
        seam.refusals(ActivationRefusalEvent(target: target, refusal: .mounted))
        #expect(host.fakeMessages.postNotificationCalls == [MountSettings.vanilla.doorRefusal])
    }

    @Test func aMountOfUnknownRaceUsesTheFallbackDismount() {
        let mounts = MountWorldAdapter(game: host, stage: nil)
        #expect(mounts.dismountOffset(of: Self.actor) == RaceProperties.MountOffsets
            .fallbackDismount)
    }

    @Test func withoutAnIdentityThePlayerHasNoLookOrGraph() {
        let player = PlayerWorldAdapter(game: host, stage: nil)
        #expect(player.playerAppearanceOverride == nil)
        #expect(player.playerBehaviorProject == nil)
        #expect(player.playerLeftHand == nil)
        host.fakeMapWorld.settingTextsResult = GameSettingTexts<ActorResourcePath>.vanilla
        #expect(player.firstPersonSkeletonPath.lowercased().hasSuffix("skeleton.nif"))
    }

    @Test func withoutARendererOrRecordsNoIdlePlacesAreKnown() {
        let idles = IdlePlacementAdapter(game: host)
        #expect(idles.idleReferencePlacements() == nil)
        #expect(idles.packageIdleList(FormID(0x10)) == nil)
    }

    @Test func withoutResidentActorsNoActorMakesASound() {
        let events = ActorGraphGraphEventsAdapter(game: host, state: ActorGraphPartState())
        #expect(events.actorSoundSources().isEmpty)
    }

    @Test func thePlayerSpeedScaleReadsWornWeightAndTheDrawnWeapon() {
        let host = ActorHost()
        let store = GameSettingStore(plugins: [])
        let speeds = MovementSpeedSettings.resolve(store: store)
        let scale = PlayerSpeedScale.provider(settings: store, game: host)
        #expect(scale() == speeds.movement(wornWeight: 0, weaponDrawn: false, speedMult: 100))
        host.fakeInventory.armourWeights.playerWornArmourWeight = 50
        host.fakeCombat.isWeaponDrawn = true
        #expect(scale() == speeds.movement(wornWeight: 50, weaponDrawn: true, speedMult: 100))
    }
}
