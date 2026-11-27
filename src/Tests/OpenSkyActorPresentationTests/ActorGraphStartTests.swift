// A started graph publishes into the pose buffer its actor's playback reads.

@testable import OpenSkyActorPresentation
@testable import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
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
        let started = try Self.started(behavior: BehaviorProjectFixture.behavior)
        let graphs = started.graphs
        #expect(graphs.pose(of: Self.actor) == nil)

        graphs.tick(deltaTime: 0)

        #expect(graphs.pose(of: Self.actor) != nil)
        #expect(started.playback.hasBone(named: "Root"))
    }

    /// The seat entry waits for the update after `moveStop`, so the graph has left its walk.
    @Test func anEventRaisedAsTheDriveStopsFollowsTheStop() throws {
        let behavior = HKBBehaviorGraph(
            name: nil, userData: 0, variableMode: 0, rootGenerator: nil,
            rootGeneratorClassName: nil,
            data: BehaviorFixture.graphData(events: ["moveStart", "moveStop", "Sit"]),
            unresolved: []
        )
        let started = try Self.started(behavior: behavior)
        let graphs = started.graphs
        graphs.tick(deltaTime: 0)
        graphs.setMotion(ActorGraphMotion(isMoving: true), for: Self.actor)
        graphs.tick(deltaTime: 0.1)
        graphs.setMotion(.still, for: Self.actor)

        #expect(graphs.raise("Sit", on: Self.actor))
        #expect(!graphs.raise("Unknown", on: Self.actor))
        graphs.tick(deltaTime: 0.1)
        #expect(graphs.readout(for: Self.actor)?.recentEvents.last == "moveStop")
        graphs.tick(deltaTime: 0.1)
        #expect(graphs.readout(for: Self.actor)?.recentEvents.last == "Sit")
    }

    /// The coordinator holds its world weakly, so the world rides along.
    private struct Started {
        let graphs: ActorGraphCoordinator
        let playback: ActorAnimationPlayback
        let world: StartWorld
    }

    private static func started(behavior: HKBBehaviorGraph) throws -> Started {
        let project = try BehaviorProjectFixture.asset()
        let asset = try BehaviorProjectAsset(
            projectPath: project.projectPath, behaviorPath: project.behaviorPath,
            objectGraph: BehaviorProjectFixture.objectGraph(), behavior: behavior,
            skeleton: BehaviorProjectFixture.rig, ragdollSkeleton: nil,
            rigPath: project.rigPath, clipPaths: []
        )
        let world = StartWorld(ActorGraphCandidate(
            key: actor, projectPath: asset.projectPath, feet: .zero, rotationZ: 0
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
        return Started(graphs: graphs, playback: playback, world: world)
    }
}
