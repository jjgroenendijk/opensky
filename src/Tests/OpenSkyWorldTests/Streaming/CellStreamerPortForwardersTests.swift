// The streamer answers each port call through the part that owns it. A streamer with no
// cell attached answers with empty values.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyNavigation
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import OpenSkyWorldInterface
import OpenSkyWorldState
import OpenSkyWorldTesting
import simd
import Testing

@MainActor
struct CellStreamerPortForwardersTests {
    private static let actor = ReferenceKey.plugin(name: "test.esm", objectID: 0x9000)

    private let streamer = CellStreamerFixture.makeStreamer(
        runner: ManualCellBuildRunner(), radius: 0
    )

    @Test func anEmptyStreamerHoldsNoReferences() {
        #expect(streamer.activateChildren(of: Self.actor).isEmpty)
        #expect(streamer.referenceEntry(formID: FormID(0x9000)) == nil)
        #expect(streamer.referenceEntry(key: Self.actor) == nil)
        #expect(streamer.residentEntries().isEmpty)
        #expect(streamer.residentActorEntries().isEmpty)
        #expect(streamer.pluginPlacement(of: Self.actor) == nil)
        #expect(streamer.cellLocation(of: Self.actor) == nil)
        #expect(streamer.residentReferenceCount == 0)
        #expect(streamer.residentAnimatedVehicles().isEmpty)
    }

    @Test func anEmptyStreamerHasNothingInFlight() {
        #expect(!streamer.startAreaReady)
        #expect(streamer.inFlightCellCount == 0)
        #expect(streamer.pendingCompletionCount == 0)
        #expect(streamer.queuedRequestCount == 0)
        #expect(!streamer.isInterior)
    }

    @Test func callsOnAnEmptyStreamerChangeNothing() {
        streamer.setActorProp(ActorPropAttachment(modelPath: "a.nif", bone: "b"), on: FormID(1))
        streamer.poseMovingCollision { _ in nil }
        streamer.leaveInterior(camera: .demo)
        #expect(!streamer.isInterior)
        #expect(streamer.residentReferenceCount == 0)
    }

    @Test func doorTransitionHooksAreStored() {
        streamer.onDoorTransitionStarted = {}
        streamer.onDoorTransitionFinished = { _ in }
        #expect(streamer.onDoorTransitionStarted != nil)
        #expect(streamer.onDoorTransitionFinished != nil)
    }

    @Test func everyMovementHookIsStored() {
        let actors = streamer.actors
        actors.npcMovementConfiguration = .synthetic
        actors.onNPCLocomotionDrive = { _ in }
        actors.onNPCPosesChanged = { _ in }
        actors.onNPCDoorCrossing = { _, _ in }
        actors.onNPCLanding = { _, _ in }
        actors.onNPCCellHandoff = { _ in }
        actors.npcStandingActors = { [] }
        actors.npcMovementSpeeds = { _ in nil }
        actors.npcBodyHalfExtents = { _ in SIMD3(1, 1, 1) }
        actors.npcWaterPushRace = { _ in .normal }
        #expect(actors.onNPCDoorCrossing != nil)
        #expect(actors.onNPCLanding != nil)
        #expect(actors.onNPCCellHandoff != nil)
        #expect(actors.npcMovementSpeeds?(Self.actor) == nil)
        #expect(actors.npcBodyHalfExtents?(Self.actor) == SIMD3(1, 1, 1))
        #expect(actors.npcWaterPushRace?(Self.actor) == .normal)
        #expect(actors.cellStreamer === streamer)
    }
}
