// What `game state actors` shows of an actor whose graph has not started.

@testable import OpenSkyActorPresentation
import OpenSkyFormatsESM
import OpenSkyWorldInterface
import Testing

@MainActor
private final class OneActorGraphWorld: ActorGraphWorld {
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
struct ActorGraphReadoutTests {
    private static let actor = ReferenceKey.plugin(name: "test.esm", objectID: 0x500)
    private static let project = "Actors\\Character\\DefaultMale.hkx"

    @Test func anActorWithoutAGraphReadsItsProjectLoadState() {
        let world = OneActorGraphWorld(ActorGraphCandidate(
            key: Self.actor, projectPath: Self.project, feet: .zero, rotationZ: 0
        ))
        let graphs = ActorGraphCoordinator(world: world) { nil }
        let loading = graphs.readout(for: Self.actor)
        #expect(loading?.status == "loading")
        #expect(loading?.project == Self.project)
        #expect(loading?.hasPose == false)
        graphs.projects[Self.project] = .failed("no file")
        #expect(graphs.readout(for: Self.actor)?.status == "failed: no file")
        let other = ReferenceKey.plugin(name: "test.esm", objectID: 0x501)
        #expect(graphs.readout(for: other) == nil)
    }

    @Test func aTickStartsNoGraphForAnActorWithoutAPlayback() {
        let world = OneActorGraphWorld(ActorGraphCandidate(
            key: Self.actor, projectPath: Self.project, feet: .zero, rotationZ: 0
        ))
        let graphs = ActorGraphCoordinator(world: world) { nil }
        graphs.tick(deltaTime: 0)
        #expect(graphs.readout(for: Self.actor)?.hasPose == false)
        #expect(graphs.readout(for: Self.actor)?.status == "loading")
    }
}
