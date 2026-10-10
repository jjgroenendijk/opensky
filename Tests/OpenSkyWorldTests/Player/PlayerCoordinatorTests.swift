// The player shell against fake worlds: graph loading failures, the body
// rebuild on an equipment change, and the two panel snapshots.

import Foundation
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import Testing

@MainActor
struct PlayerCoordinatorTests {
    private static func session() -> (PlayerCoordinator, FakePlayerWorld) {
        let input = CameraInputState()
        let world = FakePlayerWorld()
        let player = PlayerCoordinator(input: input)
        player.attach(world: world)
        return (player, world)
    }

    @Test
    func noMountedArchivesIsReported() {
        let (player, _) = Self.session()
        #expect(!player.wireBody(source: FakePlayerRigSource()))
        #expect(player.failureReason == PlayerBodyError.noFileSystem.localizedDescription)
    }

    @Test
    func aMissingBehaviorFileIsReportedAndNothingAttaches() {
        let (player, world) = Self.session()
        let provider = FakePlayerRigSource(fileSystem: InMemoryFileSource())
        #expect(!player.wireBody(source: provider))
        let expected = PlayerBodyError.behavior(.missing(PlayerBehaviorGraph.behaviorPath))
        #expect(player.failureReason == expected.localizedDescription)
        #expect(player.graph == nil)
        #expect(world.playerLocomotion?.graph == nil)
        #expect(provider.bodyRequests.isEmpty)
    }

    @Test
    func attachingAGraphBuildsTheBodyAndRecordsBothFailures() {
        let (player, world) = Self.session()
        let provider = FakePlayerRigSource()
        let graph = PlayerBehaviorGraph.fixture()
        player.attach(
            graph: graph,
            firstPerson: .failure(PlayerBehaviorGraphError.noGraph("first")),
            source: provider
        )
        #expect(player.failureReason == nil, "the body is still assembling")
        player.drainClipLoads()
        #expect(world.playerLocomotion?.graph === graph.instance)
        #expect(world.playerLocomotion?.firstPersonGraph == nil)
        #expect(provider.bodyRequests.count == 1)
        #expect(provider.rigRequests == 0)
        let body = PlayerBodyError.noRenderableGeometry(["no skin"])
        #expect(player.failureReason == body.localizedDescription)
        let firstPerson = PlayerBodyError.behavior(.noGraph("first"))
        #expect(player.firstPersonFailureReason == firstPerson.localizedDescription)
    }

    @Test
    func bothRigsRebuildOnlyWhenTheEquippedSetChanges() {
        let (player, world) = Self.session()
        let provider = FakePlayerRigSource()
        player.attach(
            graph: .fixture(), firstPerson: .success(.fixture()), source: provider
        )
        #expect(world.playerLocomotion?.firstPersonGraph != nil)
        player.refreshBody()
        #expect(provider.bodyRequests.count == 1)
        world.playerEquippedSet = [FormID(0x12EB7)]
        player.refreshBody()
        #expect(provider.bodyRequests.last == [FormID(0x12EB7)])
        #expect(provider.rigRequests == 2)
        #expect(provider.requests.map(\.generation) == [1, 1, 2, 2])
        player.drainClipLoads()
        #expect(player.firstPersonFailureReason != nil)
    }

    @Test
    func withoutARendererBothSnapshotsAreUnavailable() {
        let (player, world) = Self.session()
        world.playerLocomotion = nil
        world.firstPersonFOVYRadians = nil
        world.firstPersonArmsEnabled = nil
        #expect(player.playerLocomotionSnapshot == .unavailable)
        #expect(player.firstPersonSnapshot == .unavailable)
        #expect(player.firstPersonArmsEnabled)
        #expect(player.forcedLocomotionGait == nil)
        #expect(!player.raiseLocomotionEvent(named: "JumpUp"))
    }

    @Test
    func theLocomotionPanelReadsAndDrivesTheBridge() {
        let (player, world) = Self.session()
        let input = player.input
        world.isPlayerGrounded = false
        player.forcedLocomotionGait = .sprint
        player.isSneaking = true
        #expect(input.isSneaking)
        player.isSneaking = true
        #expect(input.isSneaking)
        let snapshot = player.playerLocomotionSnapshot
        #expect(snapshot.rendererAvailable)
        #expect(snapshot.forcedGait == .sprint)
        #expect(snapshot.bindings.map(\.isActive) == [false, false, true, true])
        #expect(snapshot.variables.allSatisfy { $0.value == nil })
    }

    @Test
    func theFirstPersonPanelReadsAndWritesTheCamera() {
        let (player, world) = Self.session()
        player.firstPersonFOVYDegrees = 90
        #expect(abs(player.firstPersonFOVYDegrees - 90) < 0.001)
        player.firstPersonArmsEnabled = false
        #expect(world.firstPersonArmsEnabled == false)
        let snapshot = player.firstPersonSnapshot
        #expect(snapshot.rendererAvailable)
        #expect(!snapshot.rigAttached)
        #expect(snapshot.droppedPieceCount == 0)
    }
}
