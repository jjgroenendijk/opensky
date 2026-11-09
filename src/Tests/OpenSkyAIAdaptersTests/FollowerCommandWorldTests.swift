// The follower command world says favour lines and moves, holds, and releases followers.

import OpenSkyAIAdapters
import OpenSkyAIPackages
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkySessionTesting
import OpenSkyWorldInterface
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
        #expect(host.fakeStreamer.activateCalls.isEmpty)
    }

    @Test func withoutATargetAPressIsNotTaken() {
        #expect(!adapter.takeActivation())
        #expect(adapter.pickReach == InteractionRay.defaultMaximumDistance)
    }

    @Test func followersMoveStopHoldAndRelease() {
        host.fakeAiWorld.movePackageActorResult = .started
        host.fakeAiWorld.packageActorPositionResult = .one
        #expect(adapter.moveFollower(Self.follower, to: .one))
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
        adapter.bringFollowers(into: FakeCellScenePort())
    }

    @Test func anUnknownTargetCannotBeCommanded() {
        #expect(adapter.commandTarget(Self.follower) == nil)
        #expect(host.fakeStreamer.referenceEntryKeyCalls == [Self.follower])
    }
}
