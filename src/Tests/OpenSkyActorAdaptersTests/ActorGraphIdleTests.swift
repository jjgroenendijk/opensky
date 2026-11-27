// The actor graph, animation event, idle, and object animation worlds forward to their ports.

import Foundation
import OpenSkyActorAdapters
import OpenSkyActorPresentation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkySessionInterface
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
        #expect(!events.playSoundType(2, source: Self.actor, at: .zero), "no sound director")
        events.endAnimationSounds(source: Self.actor)
    }

    /// A draw plays NAM9; a swing starts the NAM7 loop with TNAM; the end of the attack
    /// stops the loop. No session means no sound.
    @Test func weaponEventsPlayTheHeldWeaponsSounds() throws {
        let events = AnimationEventWorldAdapter(game: host, stage: nil)
        #expect(!events.playWeaponSound(.draw, source: Self.actor, at: .zero))
        let sword = FormID(0x300)
        let file = try ESMFixture.plugin(records: [ESMFixture.record(
            "WEAP", formID: sword.rawValue,
            data: ESMFixture.field("DATA", InventoryFixture.weaponData(
                value: 10, weight: 5, damage: 7
            )) + InventoryFixture.formIDField("NAM9", 0x61)
                + InventoryFixture.formIDField("NAM7", 0x64)
                + InventoryFixture.formIDField("TNAM", 0x63)
        )])
        host.fakeCombat.items = ItemDefinitionStore(file: file)
        host.fakeInventory.scriptItems.scriptEquippedWeaponResult = .some(sword)
        let session = FakeGameSessionPort()
        let director = FakeWorldAudioSoundDirectorPort()
        director.playSoundResult = true
        session.soundDirector = director
        host.gameSession = session
        #expect(events.playWeaponSound(.draw, source: Self.actor, at: .zero))
        #expect(events.playWeaponSound(.swing(leftHand: false), source: Self.actor, at: .zero))
        #expect(events.playWeaponSound(.attackEnd, source: Self.actor, at: .zero))
        #expect(!events.playWeaponSound(.sheathe, source: Self.actor, at: .zero))
        #expect(director.playSoundCalls.map(\.formID) == [FormID(0x61), FormID(0x64), FormID(0x63)])
        #expect(director.stopSoundCalls.map(\.formID) == [FormID(0x64)])
    }

    @Test func theClothWorldFindsNoCapeWithoutAScene() {
        let cloth = ClothWorldAdapter(game: host, stage: nil, isEnabled: false)
        #expect(cloth.clothPlaybacks.isEmpty)
        cloth.coordinator.tick(deltaTime: 0.016)
        #expect(!cloth.coordinator.readout.isEnabled)
        #expect(cloth.coordinator.readout.capes.isEmpty)
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
        host.fakeStreamer.actors.turnActorResult = 0.5
        #expect(idles.turnActor(Self.actor, toHeading: 1, within: 0.1) == 0.5)
        #expect(host.fakeStreamer.actors.turnActorCalls.map(\.actor) == [Self.actor])
        #expect(idles.synchronizedMark(of: .player) == nil)
        #expect(idles.synchronizedMark(of: Self.actor) == nil)
    }

    @Test func anActorWithoutARunningGraphRunsNoGraphOfItsOwn() throws {
        let idles = IdleWorldAdapter(game: host, stage: nil)
        let graphs = try #require(host.fakeActorGraphWorld.graphs as? FakeActorGraphPort)
        #expect(!idles.runsOwnGraph(Self.actor))
        #expect(graphs.instanceCalls == [Self.actor])
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
