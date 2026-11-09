// A started graph publishes into the pose buffer its actor's playback reads.

@testable import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyWorldInterface
import Testing

@MainActor
private final class StartWorld: ActorGraphWorld {
    let candidate: ActorGraphCandidate

    init(_ candidate: ActorGraphCandidate) {
        self.candidate = candidate
    }

    var actorGraphViewer: SIMD3<Float>? {
        nil
    }

    func actorGraphCandidates() -> [ActorGraphCandidate] {
        [candidate]
    }

    func actorGraphFired(_: String, from _: ReferenceKey) {}

    func animationWaitFinished(token _: UInt64, fired _: Bool) {}

    func applyRootMotion(_: ActorRootMotionStep, to _: ReferenceKey) {}
}

@MainActor
struct ActorGraphStartTests {
    private static let actor = ReferenceKey.plugin(name: "test.esm", objectID: 0x600)

    @Test func aStartedGraphHandsItsPoseToThePlayback() throws {
        let asset = try BehaviorProjectFixture.asset()
        let world = StartWorld(ActorGraphCandidate(
            key: Self.actor, projectPath: asset.projectPath, feet: .zero, rotationZ: 0
        ))
        let graphs = ActorGraphCoordinator(world: world) { nil }
        let loaded = LoadedActorGraphProject(
            asset: asset, referencePaths: [:], boneLOD: nil, speedSamples: nil
        )
        graphs.projects[asset.projectPath] = .ready(
            ActorGraphCoordinator.Project(loaded, files: InMemoryFileSource())
        )
        let clip = try BehaviorFixture.splineClip(boneIndex: 0)
        let playback = ActorAnimationPlayback(
            actor: FormID(0x600),
            clip: ActorAnimationClip(
                skeleton: BehaviorProjectFixture.rig, animation: clip.animation,
                binding: clip.binding
            ),
            models: []
        )
        graphs.actorPlayback = { _ in playback }
        #expect(graphs.pose(of: Self.actor) == nil)

        graphs.tick(deltaTime: 0)

        #expect(graphs.pose(of: Self.actor) != nil)
        #expect(playback.hasBone(named: "Root"))
    }
}
