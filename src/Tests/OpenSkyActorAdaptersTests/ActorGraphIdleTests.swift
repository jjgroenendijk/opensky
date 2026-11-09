// The actor graph, animation event, idle, and object animation worlds forward to their ports.

import OpenSkyActorAdapters
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkySessionTesting
import OpenSkyWorldInterface
import Testing

@MainActor
struct ActorGraphIdleTests {
    private let host = ActorHost()
    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)

    @Test func graphReadsGoThroughTheGraphPort() {
        let graphs = ActorGraphWorldAdapter(game: host, stage: nil)
        host.fakeActorGraphs.variableResolutionResult = .empty
        _ = graphs.graphVariableResolution()
        graphs.animationWaitFinished(token: 4, fired: true)
        #expect(host.fakeActorGraphs.variableResolutionCalls.count == 1)
        #expect(host.fakeObjectAnimationWorld.answerWaitCalls.map(\.token) == [4])
        #expect(graphs.actorGraphViewer == nil)
    }

    @Test func animationEventsReachCameraHeadAndEffectGraphs() {
        let events = AnimationEventWorldAdapter(game: host, stage: nil)
        events.shakeCamera(from: .one, strength: 2)
        events.setHeadTracking(true, for: Self.actor)
        events.sendEffectGraphEvent("FootLeft", from: Self.actor)
        events.sendScriptAnimationEvent("Hit", from: Self.actor)
        #expect(host.fakeCinematicCamera.startShakeCalls.map(\.strength) == [2])
        #expect(host.fakeHeadTracking.setHeadTrackingCalls.map(\.actor) == [Self.actor])
        #expect(host.fakeEffectGraphs.deliverCalls.map(\.event) == ["FootLeft"])
        #expect(events.playAnimationSound(editorID: "NPCFoot", source: Self.actor, at: .zero))
        events.stopAnimationSound(editorID: "NPCFoot", source: Self.actor)
        events.releaseAnimationSound(editorID: "NPCFoot", source: Self.actor)
    }

    @Test func idleCallsReachVehiclesAndTheAIWorld() {
        let idles = IdleWorldAdapter(game: host, stage: nil)
        host.fakeAiWorld.moveActorResult = .started
        host.fakeWorldState.nextJournalSequence = 7
        idles.idleAnimationEvent("SitDown", on: Self.actor)
        #expect(idles.moveActor(Self.actor, to: .one) == .started)
        #expect(idles.idleStateSequence == 7)
        #expect(host.fakeVehicleWorld.handleIdleAnimationEventCalls.map(\.name) == ["SitDown"])
        #expect(host.fakeAiWorld.moveActorCalls.map(\.actor) == [Self.actor])
        #expect(idles.idleAnimationTime == nil)
    }

    @Test func aTurnGoesThroughTheStreamer() {
        let idles = IdleWorldAdapter(game: host, stage: nil)
        host.fakeStreamer.turnActorResult = 0.5
        #expect(idles.turnActor(Self.actor, toHeading: 1, within: 0.1) == 0.5)
        #expect(host.fakeStreamer.turnActorCalls.map(\.actor) == [Self.actor])
        #expect(idles.synchronizedMark(of: .player) == nil)
    }

    @Test func anObjectEventFallsBackToTheActorGraph() throws {
        let objects = ObjectAnimationWorldAdapter(game: host, stage: nil)
        let graphs = try #require(host.fakeActorGraphWorld.graphs as? FakeActorGraphPort)
        graphs.raiseResult = true
        #expect(objects.playAnimation("Open", on: Self.actor))
        #expect(graphs.raiseCalls.map(\.event) == ["Open"])
        host.fakeEffectGraphs.deliverResult = true
        #expect(objects.playSubGraphAnimation("Glow", on: Self.actor))
        #expect(objects.residentAnimatedObjects().isEmpty)
        #expect(objects.residentSequenceDoors().isEmpty)
        #expect(objects.residentNodeAnimations().isEmpty)
        #expect(objects.nodeControllerViewer == nil)
    }
}
