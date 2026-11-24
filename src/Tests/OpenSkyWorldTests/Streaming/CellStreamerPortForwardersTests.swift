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
        // The second read answers from the remembered placement.
        #expect(streamer.pluginPlacement(of: Self.actor) == nil)
        #expect(streamer.cellLocation(of: Self.actor) == nil)
        #expect(streamer.residentReferenceCount == 0)
        #expect(streamer.residentAnimatedVehicles().isEmpty)
        #expect(streamer.residentWorldspace == streamer.worldspaceEditorID)
        #expect(streamer.playerCellLocation == nil, "no cell has streamed in")
    }

    @Test func aReferenceSourceWithoutCellsNamesNoPlayerCell() {
        #expect(BareReferenceSource().playerCellLocation == nil)
        #expect(BareReferenceSource().residentWorldspace == nil)
    }

    /// An exterior home names its worldspace, so a city cell is not read as Tamriel's.
    @Test func aPluginHomeOutsideNamesItsWorldspace() throws {
        let fixtures = try CellSceneFixture()
        let plugin = try ESMFile(data: fixtures.plugin(
            worldspaceEditorID: "RiftenWorld",
            temporaryRefs: fixtures.refrRecord(formID: 0x210, base: 0x100)
        ))
        streamer.placedRecords = PlacedRecordLookup(
            index: LoadOrderRecordIndex(plugins: [("Skyrim.esm", plugin)])
        )
        let home = try #require(streamer.pluginPlacement(
            of: .plugin(name: "Skyrim.esm", objectID: 0x210)
        ))
        #expect(home.home == .exterior(CellCoordinate(x: 0, y: 0)), "the cell its position is in")
        #expect(home.worldspace == "RiftenWorld")
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
        streamer.onDoorTransitionStarted = { _ in }
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
        actors.npcMovementSpeeds = { _ in ActorMovementSpeeds() }
        actors.npcBodyHalfExtents = { _ in SIMD3(1, 1, 1) }
        actors.npcHeightScale = { _ in 1.1 }
        actors.npcWaterPushRace = { _ in .normal }
        #expect(actors.onNPCDoorCrossing != nil)
        #expect(actors.onNPCLanding != nil)
        #expect(actors.onNPCCellHandoff != nil)
        #expect(actors.npcMovementSpeeds?(Self.actor) == ActorMovementSpeeds())
        #expect(actors.npcBodyHalfExtents?(Self.actor) == SIMD3(1, 1, 1))
        #expect(actors.npcHeightScale?(Self.actor) == 1.1)
        #expect(actors.npcWaterPushRace?(Self.actor) == .normal)
        #expect(actors.cellStreamer === streamer)
    }
}

/// A reference source that knows no reference, so every default member answers.
private final class BareReferenceSource: PapyrusWorldReferenceSource {
    func referenceEntry(formID _: FormID) -> RuntimeReferenceEntry? {
        nil
    }

    func referenceEntry(key _: ReferenceKey) -> RuntimeReferenceEntry? {
        nil
    }

    func cellLocation(of _: ReferenceKey) -> CellSceneLocation? {
        nil
    }

    func activateChildren(of _: ReferenceKey) -> [ActivateChild] {
        []
    }
}
