// The parts the AI adapters keep their narrower jobs in answer through their owners.

import OpenSkyActorsInterface
@testable import OpenSkyAIAdapters
import OpenSkyAIPackages
import OpenSkyFormatsAnimation
@testable import OpenSkyFormatsESM
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyRenderCore
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct AIAdapterPartsTests {
    private let host = AIHost()
    private let adapter: AIWorldAdapter
    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let chair = ReferenceKey.plugin(name: "base.esm", objectID: 0x30)
    private static let seat = PackageSeat(
        furniture: chair,
        index: 0,
        seat: FurnitureSeat(position: .zero, heading: 0, animationType: 1, keyword: nil)
    )

    init() {
        host.fakeStreamer.residents.residentReferenceIndexResult = .empty
        adapter = AIWorldAdapter(game: host, stage: nil)
    }

    @Test func onlyAnObjectOrReferenceSelectorNamesAForm() {
        let references = adapter.packageActs.references
        #expect(references
            .selectedForm(Package.Target(rawKind: 2, value: 10, countOrDistance: 0)) == nil)
        #expect(references
            .selectedForm(Package.Target(rawKind: 1, value: 10, countOrDistance: 0)) == nil)
    }

    @Test func withoutScriptsAPackageTargetHasNoKey() {
        let target = Package.Target(rawKind: 0, value: 0x701, countOrDistance: 0)
        #expect(adapter.packageMoves.places.packageTargetKey(target, aliasQuest: nil) == nil)
    }

    @Test func theWorldsForwardActivationAndSituations() {
        #expect(adapter.worlds.activate(Self.actor, by: Self.actor) == .failed)
        #expect(adapter.worlds.packageSituations(of: []).isEmpty)
    }

    @Test func aPlayerAtRestMakesNoActionSound() {
        let traits = adapter.frames.detectionSense.playerDetectionTraits(at: .zero, eyeHeight: 120)
        #expect(traits.actionSound == 0)
    }

    @Test func withoutACameraThereIsNoGroundTarget() {
        let followers = FollowerCommandWorldAdapter(game: host, stage: nil)
        #expect(followers.checks.groundTarget() == nil)
    }

    @Test func anActorSeatsStandsAndRestsThroughThePoses() {
        let occupancy = FurnitureOccupancy(seat: Self.seat, entry: 1)
        let pose = FurniturePose(root: [10, 0, 0], heading: 0)
        adapter.worlds.placeSeated(Self.actor, in: occupancy)
        adapter.worlds.placeStanding(Self.actor, from: occupancy)
        adapter.worlds.moveFurnitureActor(Self.actor, to: pose)
        adapter.worlds.finishStanding(Self.actor, at: pose)
        #expect(host.fakeStreamer.actors.restActorCalls.map(\.actor) == [
            Self.actor,
            Self.actor,
            Self.actor
        ])
    }

    @Test func withoutScriptsAPackageNamesNoPlaceOrReference() {
        let location = Package.Location(rawKind: 0, value: 0x700, radius: 0)
        let target = Package.Target(rawKind: 0, value: 0x701, countOrDistance: 0)
        #expect(adapter.worlds
            .packagePlace(of: location, actor: Self.actor, aliasQuest: nil) == nil)
        #expect(adapter.worlds
            .packagePatrolPath(from: target, actor: Self.actor, aliasQuest: nil) == nil)
        #expect(adapter.worlds.packageReference(target, actor: Self.actor, aliasQuest: nil) == nil)
        #expect(!adapter.worlds.isWithin(location, actor: Self.actor))
        #expect(adapter.worlds.packageAliasStacks().isEmpty)
    }

    @Test func withoutScriptsCastsShoutsAndFindsFail() {
        let target = Package.Target(rawKind: 1, value: 0x701, countOrDistance: 0)
        #expect(adapter.worlds
            .packageAction(.cast(target, at: Self.actor), actor: Self.actor) == .failed)
        #expect(adapter.worlds
            .packageAction(.shout(target, at: Self.actor), actor: Self.actor) == .failed)
        let find = PackageAction.find(target, center: .zero, radius: 0)
        #expect(adapter.worlds.packageAction(find, actor: Self.actor) == .found([]))
    }

    @Test func aPackageNearTheActorUsesItsLivePosition() {
        host.fakeStreamer.actors.npcTransformResult = ReferenceTransformOverride(position: .one)
        let places = adapter.packageMoves.places
        let nearSelf = Package.Location(rawKind: 12, value: 0, radius: 5)
        #expect(places.packagePlace(of: nearSelf, actor: Self.actor, aliasQuest: nil)?
            .point == .one)
        let editor = Package.Location(rawKind: 3, value: 0, radius: 5)
        #expect(places.packagePlace(of: editor, actor: Self.actor, aliasQuest: nil) == nil)
        host.fakeStreamer.actors.npcTransformResult = nil
        #expect(adapter.packageMoves.packageActorPosition(Self.actor) == nil)
    }

    @Test func aCameraOverEmptyGroundCommandsNothing() {
        let session = FakeGameSessionPort()
        session.freeFlyCameraValue = FreeFlyCamera(position: [1, 2, 3], yaw: 0, pitch: 0)
        host.gameSession = session
        host.fakeFollowerCommands.isChoosing = true
        host.fakeFollowerCommands.settingsValue = .vanilla
        let followers = FollowerCommandWorldAdapter(game: host, stage: nil)
        #expect(followers.takeActivation())
        #expect(host.fakeFollowerCommands.commandCalls.count == 1)
    }

    @Test func aTeleportedPlayerLeavesTheSeat() throws {
        let session = FakeGameSessionPort()
        host.gameSession = session
        host.fakeFurniture.occupancies[.player] = FurnitureOccupancy(seat: Self.seat, entry: 1)
        adapter.seating.poses.releaseMovedPlayer()
        #expect(host.fakeFurniture.vacateCalls == [.player])
        let idles = try #require(host.fakeIdleWorld.idles as? FakeIdlePort)
        #expect(idles.leaveFurnitureCalls.map(\.actor) == [.player])
    }

    @Test func aSeatedPlayerIsPlacedOnThePose() {
        let session = FakeGameSessionPort()
        host.gameSession = session
        adapter.worlds.moveFurnitureActor(.player, to: FurniturePose(root: [10, 0, 0], heading: 0))
        #expect(session.seatPlayerCalls.count == 1)
    }

    @Test func aFinishedRootMotionReportsItsEnd() throws {
        let idles = try #require(host.fakeIdleWorld.idles as? FakeIdlePort)
        #expect(adapter.worlds.furnitureMotion(of: Self.actor) == nil)
        let motion = AnimationRootMotion(duration: 1, translations: [], rotations: [])
        idles.rootMotionResult = (motion: motion, elapsed: 2)
        #expect(adapter.worlds.furnitureMotion(of: Self.actor)?.isFinished == true)
    }
}
