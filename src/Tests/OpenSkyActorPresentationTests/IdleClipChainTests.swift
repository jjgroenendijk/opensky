// An idle's clips over a synthetic one-bone clip: the chain the clip loader builds,
// a playing clip's bones, and the marker claims and readouts with no markers.

@testable import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyConditions
import OpenSkyEngineTesting
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyWorldInterface
import Testing

@MainActor
struct IdleClipChainTests {
    private static let skeleton = ActorClipLoader.playerSkeletonPath

    nonisolated private static func clip() throws -> ActorAnimationClip {
        let spline = try BehaviorFixture.splineClip(boneIndex: 0)
        return ActorAnimationClip(
            skeleton: BehaviorProjectFixture.rig, animation: spline.animation,
            binding: spline.binding
        )
    }

    private static func plan() -> IdlePlaybackPlan {
        IdlePlaybackPlan(
            event: "IdleSit", path: .namedClip, clipPath: "enter.hkx", prop: .none,
            followUps: [IdlePlanSegment(clipPath: "loop.hkx", loops: true, triggers: [])]
        )
    }

    @Test func aChainWaitsForItsClipsThenHoldsTheLastOne() throws {
        let clip = try Self.clip()
        let loader = ActorClipLoader(worker: ImmediateAssetLoadWorker { _ in clip })
        #expect(loader.isLoading(Self.plan(), skeleton: Self.skeleton))
        _ = loader.drain()
        #expect(!loader.isLoading(Self.plan(), skeleton: Self.skeleton))
        let chain = try #require(loader.chain(
            of: Self.plan(),
            skeleton: Self.skeleton,
            holds: true
        ))
        #expect(chain.followUps.count == 1)
        #expect(chain.holdsLast)
        #expect(chain.first.duration == clip.animation.duration)
        #expect(chain.first.marks.isEmpty)
    }

    @Test func aPlayingClipPosesItsRootBoneUntilItEnds() throws {
        var playing = try IdleCoordinator.Playing(
            clip: Self.clip(), start: 0, end: 10, hasProp: false
        )
        #expect(playing.boneMatrix(named: "Root", at: 0.1) != nil)
        #expect(playing.bone(named: "Root", at: 0.1) != nil)
        #expect(playing.boneForward(named: "Root", at: 0.1) != nil)
        #expect(playing.bone(named: "Root", at: 20) == nil)
        #expect(playing.boneMatrix(named: "Missing", at: 0.1) == nil)
        #expect(playing.applyAnimationObject("AnimObjectLoad") == nil)
    }

    @Test func noConditionsFailAndAnAttackNamesBothActors() {
        #expect(IdleConditionChecks
            .firstFailingFunction(in: [], context: ConditionContext()) == nil)
        let attack = IdleConditionChecks.attack(
            attacker: .player, target: .generated(2), kills: true
        )
        #expect(attack.kills(.player, .generated(2)) == true)
    }

    @Test func withoutMarkersNothingIsClaimedOrShown() {
        let store = IdleStore(plugins: [])
        let claims = IdleCoordinator.IdleMarkerClaims()
        claims.refresh(now: 0, store: store) { [] }
        var sessions: [ReferenceKey: IdleCoordinator.Session] = [:]
        claims.claim(actors: [:], sessions: &sessions, world: PairedIdleWorld())
        #expect(claims.markers.isEmpty)
        #expect(store.markerReadouts(claims.markers, holders: [:]).isEmpty)
        #expect(IdleCoordinator(world: nil, data: nil).markers.isEmpty)
        let data = IdleSessionData(
            store: store, files: InMemoryFileSource(),
            clips: ActorClipLoader(worker: ImmediateAssetLoadWorker { _ in try Self.clip() }),
            conditionFunctions: .empty
        )
        _ = data.planLoader()
    }
}
