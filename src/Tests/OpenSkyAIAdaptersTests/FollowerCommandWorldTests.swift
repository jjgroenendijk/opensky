// The follower command world says favour lines and moves, holds, and releases followers.

import OpenSkyAIAdapters
import OpenSkyAIPackages
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScriptingInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct FollowerCommandWorldTests {
    private let host = AIHost()
    private let adapter: FollowerCommandWorldAdapter
    private static let follower = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)

    init() {
        adapter = FollowerCommandWorldAdapter(game: host, stage: nil)
    }

    @Test func aStartedFavourSaysItsLine() {
        host.fakeDialogue.favorLineResult = FormID(0x70)
        adapter.favorStateChanged(Self.follower, isDoingFavor: true)
        adapter.favorStateChanged(Self.follower, isDoingFavor: false)
        #expect(host.fakeDialogue.favorLineCalls.map(\.subtype) == ["SHOW", "FEXT"])
        #expect(host.fakeStoryWorld.sayCalls.map(\.id) == [FormID(0x70), FormID(0x70)])
        #expect(host.fakeFollowerCommands.favorStartedCalls == [Self.follower])
        #expect(host.fakeFollowerCommands.favorEndedCalls == [Self.follower])
    }

    @Test func endingAFavourAnnouncesOnlyWhenAsked() {
        adapter.endFavor(Self.follower, announces: false)
        adapter.endFavor(Self.follower, announces: true)
        #expect(host.fakeDialogue.favorLineCalls.map(\.subtype) == ["FEXT"])
        #expect(host.fakeStoryWorld.sayCalls.isEmpty)
    }

    @Test func holdingTheUseKeyEntersCommandMode() {
        host.fakeFollowerCommands.advanceUseKeyResult = .hold(Self.follower)
        adapter.advanceUseKey(by: 1, isDown: true)
        #expect(host.fakeFollowerCommands.favorStartedCalls == [Self.follower])
        host.fakeFollowerCommands.advanceUseKeyResult = .tap(Self.follower)
        adapter.advanceUseKey(by: 1, isDown: false)
        #expect(host.fakeStreamer.residents.activateCalls.isEmpty)
    }

    @Test func theCrosshairStaysNormalUntilCommandModeRuns() {
        let texts = GameSettingTexts<FollowerCommandText>.vanilla
        #expect(adapter.crosshair(for: nil, texts: texts) == nil)
        host.fakeFollowerCommands.isChoosing = true
        host.fakeFollowerCommands.phaseValue = .choosing(follower: Self.follower)
        #expect(adapter.crosshair(for: nil, texts: texts) != nil)
        host.fakeFollowerCommands.isChoosing = false
        #expect(adapter.crosshair(for: nil, texts: texts)?.prompt == nil)
    }

    @Test func withoutATargetAPressIsNotTaken() {
        #expect(!adapter.takeActivation())
        #expect(adapter.pickReach == InteractionRay.defaultMaximumDistance)
    }

    @Test func followersMoveStopHoldAndRelease() {
        host.fakeAiWorld.movePackageActorResult = .started
        host.fakeAiWorld.packageActorPositionResult = .one
        #expect(adapter.moveFollower(Self.follower, to: .one) == .started)
        adapter.stopFollower(Self.follower)
        adapter.holdFollower(Self.follower)
        adapter.releaseFollower(Self.follower)
        #expect(adapter.followerCommandPosition(of: Self.follower) == .one)
        #expect(host.fakeAiWorld.stopPackageActorCalls == [Self.follower])
        #expect(host.fakePackages.holdCommandedCalls == [Self.follower])
        #expect(host.fakePackages.releaseCommandedCalls == [Self.follower])
    }

    @Test func withoutDataTheRulesUseTheirDefaults() {
        #expect(adapter.followerMorality(Self.follower) == FollowerCommandRules.lawfulMorality)
        #expect(adapter.followerCommandPlayerPosition == nil)
        _ = adapter.followerCommandSettings
        adapter.doors.bringFollowers(into: FakeCellScenePort())
    }

    /// A load door moves each teammate into the destination and rebuilds that cell, which
    /// an exterior the player returns to needs to draw them.
    @Test func aLoadDoorMovesTeammatesAndRebuildsTheDestination() {
        let bridge = FakePapyrusWorldStateBridgePort()
        host.fakeScripts.bridge = bridge
        let session = FakeGameSessionPort()
        host.gameSession = session
        host.fakeWorldState.sortedDirtyKeysResult = [Self.follower]
        host.fakeWorldState.componentResult = ScriptedReferenceState(
            flags: [ScriptedStateName.playerTeammate: true]
        )
        host.fakeAiWorld.packageActorActivityResult = .free
        host.fakeFollowerCommands.phaseValue = .idle
        host.fakeStreamer.lastDoorArrival = SIMD3(100, 0, 0)
        let scene = FakeCellScenePort()
        let destination = CellSceneLocation.exterior(CellCoordinate(x: 6, y: -2))
        scene.location = destination
        adapter.doors.bringFollowers(into: scene)
        #expect(bridge.relocateKeyToCalls.map(\.key) == [Self.follower])
        let placed = host.fakeWorldState.setCalls.compactMap { call in
            (call.component as? ReferenceTransformOverride).map { ($0.position, call.cell) }
        }
        #expect(placed.map(\.0) == [SIMD3(164, 0, 0)])
        #expect(placed.map(\.1) == [destination])
        let actors = host.fakeStreamer.actors
        #expect(actors.stopActorCalls == [Self.follower])
        #expect(actors.restActorCalls.map(\.transform.position) == [SIMD3(164, 0, 0)])
        #expect(host.fakeStreamer.requestRebuildCalls == [destination])
    }

    @Test func anUnknownTargetCannotBeCommanded() {
        #expect(adapter.commandTarget(Self.follower) == nil)
        #expect(host.fakeStreamer.referenceEntryKeyCalls == [Self.follower])
    }
}
