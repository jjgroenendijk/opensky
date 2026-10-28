// The player shell against fake worlds: graph loading failures, the race graph swap, the
// body rebuild on an equipment change, and the two readout snapshots.

import Foundation
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyPlayer
@testable import OpenSkyRendering
import Testing

@MainActor
struct PlayerCoordinatorTests {
    private static func session(
        source: FakePlayerRigSource? = nil
    ) -> (PlayerCoordinator, FakePlayerWorld) {
        let world = FakePlayerWorld()
        let player = PlayerCoordinator(
            input: CameraInputState(),
            world: world,
            source: source,
            graphWorker: source?.playerAssetFileSystem.map {
                ImmediateAssetLoadWorker(load: PlayerGraphKind.loader(fileSystem: $0))
            }
        )
        return (player, world)
    }

    @Test
    func noMountedArchivesIsReported() {
        let (player, _) = Self.session(source: FakePlayerRigSource())
        #expect(player.failureReason == PlayerBodyError.noFileSystem.localizedDescription)
    }

    @Test
    func withoutGameDataThereIsNoBodyAndNoFailure() {
        let (player, world) = Self.session(source: nil)
        player.requestBody()
        player.drainClipLoads()
        player.refreshBody()
        #expect(player.failureReason == nil)
        #expect(player.graph == nil)
        #expect(world.playerLocomotion?.graph == nil)
    }

    @Test
    func aMissingBehaviorFileIsReportedAtTheDrainAndNothingAttaches() {
        let provider = FakePlayerRigSource(fileSystem: InMemoryFileSource())
        let (player, world) = Self.session(source: provider)
        player.requestBody()
        player.refreshBody()
        #expect(player.failureReason == nil, "the graphs have not arrived yet")
        player.drainClipLoads()
        let expected = PlayerBodyError.behavior(.missing(PlayerBehaviorGraph.behaviorPath))
        #expect(player.failureReason == expected.localizedDescription)
        #expect(player.graph == nil)
        #expect(world.playerLocomotion?.graph == nil)
        #expect(provider.bodyRequests.isEmpty)
    }

    @Test
    func attachingAGraphBuildsTheBodyAndRecordsBothFailures() {
        let provider = FakePlayerRigSource(fileSystem: InMemoryFileSource())
        let (player, world) = Self.session(source: provider)
        let graph = PlayerBehaviorGraph.fixture()
        player.attach(
            graph: graph,
            firstPerson: .failure(PlayerBehaviorGraphError.noGraph("first"))
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
        let provider = FakePlayerRigSource()
        let (player, world) = Self.session(source: provider)
        player.attach(graph: .fixture(), firstPerson: .success(.fixture()))
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

    /// A race with its own project holds the body back until that graph loads. One that
    /// cannot load is reported once, and the body rebuilds on the character graphs.
    @Test
    func aRaceGraphThatFailsToLoadKeepsTheCharacterGraphs() {
        let provider = FakePlayerRigSource(fileSystem: InMemoryFileSource())
        let (player, world) = Self.session(source: provider)
        let graph = PlayerBehaviorGraph.fixture()
        player.attach(graph: graph, firstPerson: .success(.fixture()))
        #expect(provider.bodyRequests.count == 1)
        let project = "meshes\\actors\\werewolfbeast\\werewolfbeastproject.hkx"
        world.playerBehaviorProject = project
        world.playerEquippedSet = [FormID(0x12EB7)]
        player.refreshBody()
        #expect(provider.bodyRequests.count == 1, "the race graph is not in yet")
        player.drainClipLoads()
        player.drainClipLoads()
        let expected = PlayerBodyError.behavior(.missing(project))
        #expect(player.raceGraphFailureReason == expected.localizedDescription)
        #expect(player.graphProject == nil)
        #expect(world.playerLocomotion?.graph === graph.instance)
        #expect(provider.bodyRequests.last == [FormID(0x12EB7)])
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
