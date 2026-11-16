// The grab in the running world, over synthetic bodies: a press and hold on a loose object
// or a dead body, a tap, the spring and what breaks it, and a grab by command that turns
// the view and outlasts an Activate key that is up.

@testable import OpenSkyActorAdapters
import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRenderCore
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import OpenSkyWorldTesting
import simd
import Testing

@MainActor
struct PlayerGrabAdapterTests {
    private let host = ActorHost()
    private let session = FakeGameSessionPort()
    private let crate: ReferenceKey
    private static let reference = FormID(0x77)
    private static let base = FormID(0x700)
    private static let corpse = ReferenceKey.generated(9)

    init() throws {
        let entry = try FakeRuntimeStateWorld.referenceEntry(objectID: 0x77)
        crate = entry.key
        var world = DynamicBodyWorld()
        world.setCell(.interior(FormID(0x10)), placements: [DynamicBodyPlacement(
            key: crate, reference: Self.reference,
            definition: DynamicBodyDefinition(
                volumes: [.radial(first: [-10, 0, 0], second: [10, 0, 0], radius: 5)], mass: 8
            ),
            originPosition: SIMD3(60, 80, 100), orientation: .identityRotation
        )])
        host.fakeStreamer.dynamicBodiesValue = world
        host.fakeStreamer.referenceEntryFormIDResult = entry
        host.fakeStreamer.referenceEntryKeyResult = entry
        session.movementModeValue = .walk
        session.freeFlyCameraValue = FreeFlyCamera(position: .zero, yaw: 0, pitch: 0)
        session.walkController.capsuleValue = .standard
        host.gameSession = session
    }

    private func adapter() -> PlayerGrabAdapter {
        PlayerGrabAdapter(game: host, stage: nil, settings: .vanilla)
    }

    /// Puts the crate under the crosshair as the first collision hit.
    private func aimAtCrate() throws {
        let body = try #require(host.fakeStreamer.dynamicBodies.body(for: crate))
        host.fakeStreamer.collision.nearestCollisionHitResult = InteractionRayHit(
            reference: Self.reference, position: body.position,
            distance: simd_length(body.position)
        )
    }

    @Test func holdingActivateOnTheObjectGrabsItAndReleasingLetsGo() throws {
        try aimAtCrate()
        host.itemWeights[Self.base] = 80
        let grab = adapter()
        #expect(grab.takeActivation())
        grab.advanceUseKey(by: 0.25, isDown: true)
        #expect(grab.grabReadout.held == 0x77)
        #expect(session.locomotion.isCarryingHeavyItem)
        #expect(grab.takeActivation(), "the press that ends a hold is taken")
        grab.advanceUseKey(by: 1.0 / 60, isDown: true)
        grab.advanceUseKey(by: 1.0 / 60, isDown: false)
        #expect(grab.grabReadout.held == nil)
        #expect(grab.grabReadout.lastLetGo == "released")
        #expect(!session.locomotion.isCarryingHeavyItem)
    }

    @Test func aTapDoesNotGrabAndNothingUnderTheCrosshairIsNotTaken() throws {
        let grab = adapter()
        #expect(!grab.takeActivation())
        try aimAtCrate()
        #expect(grab.takeActivation())
        grab.advanceUseKey(by: 0.05, isDown: false)
        #expect(grab.grabReadout.held == nil)
        #expect(grab.grabReadout.phase == "idle")
    }

    @Test func theSpringHoldsAheadAndLetsGoWhenStretched() {
        let grab = adapter()
        #expect(grab.grab(crate))
        grab.steer(delta: 1.0 / 60)
        #expect(grab.grabReadout.held == 0x77)
        session.freeFlyCamera.yaw += .pi
        grab.steer(delta: 1.0 / 60)
        #expect(grab.grabReadout.held == nil)
        #expect(grab.grabReadout.lastLetGo == "stretched")
    }

    @Test func theSpringLetsGoWithoutAnAim() {
        let grab = adapter()
        #expect(grab.grab(crate))
        session.movementModeValue = .fly
        grab.steer(delta: 1.0 / 60)
        #expect(grab.grabReadout.lastLetGo == "no aim")
    }

    @Test func aDeadBodyIsHeldByItsNearestBodyAndSteered() {
        let runtime = FakeRagdollRuntimePort()
        var ragdolls = RagdollWorld()
        ragdolls.add(
            RagdollFixture.pair(origin: SIMD3(80, 0, 60)), for: Self.corpse,
            in: .interior(FormID(0x10))
        )
        runtime.worldValue = ragdolls
        runtime.isDeadResult = true
        host.fakeRagdoll.runtime = runtime
        let grab = adapter()
        #expect(grab.grab(Self.corpse))
        #expect(grab.grabReadout.body == 0)
        grab.steer(delta: 1.0 / 60)
        #expect(runtime.steerBodyCalls.first?.index == 0)
        runtime.worldValue = RagdollWorld()
        grab.steer(delta: 1.0 / 60)
        #expect(grab.grabReadout.lastLetGo == "gone")
    }

    @Test func aCommandGrabFacesTheObjectAndHoldsWithTheKeyUp() throws {
        let grab = adapter()
        #expect(grab.grab(crate))
        let body = try #require(host.fakeStreamer.dynamicBodies.body(for: crate))
        let toward = simd_normalize(body.position - session.freeFlyCamera.position)
        #expect(simd_dot(session.freeFlyCamera.forward, toward) > 0.999)
        grab.advanceUseKey(by: 1.0 / 60, isDown: false)
        #expect(grab.grabReadout.phase == "holding")
        #expect(grab.grabReadout.held == 0x77)
    }

    @Test func aPressOrTheCommandLetsGoOfACommandGrab() {
        let grab = adapter()
        #expect(grab.grab(crate))
        #expect(grab.takeActivation())
        #expect(grab.grabReadout.held == nil)
        #expect(grab.grabReadout.lastLetGo == "released")
        #expect(grab.grab(crate))
        grab.letGo()
        #expect(grab.grabReadout.held == nil)
    }
}
