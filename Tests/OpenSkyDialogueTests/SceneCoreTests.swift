// The scene readout sentences and the playing row, with plain values.

@testable import OpenSkyDialogue
import OpenSkyDialogueFixtures
@testable import OpenSkyDialogueInterface
import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
@testable import OpenSkyWorldState
import Testing

@MainActor
struct SceneCoreTests {
    @Test(arguments: [
        (SceneStep.began, "began"),
        (.phaseSkipped(0), "phase 1 skipped"),
        (.phaseStarted(1), "phase 2 started"),
        (.phaseCompleted(0, byConditions: true), "phase 1 done by conditions"),
        (.phaseCompleted(2, byConditions: false), "phase 3 done by actions"),
        (.fragment("Begin"), "fragment Begin"),
        (.fragmentUnrun("End"), "fragment End not run"),
        (.repeated, "repeated"),
        (.waitingForActors, "waiting for actors in another scene"),
        (.paused, "paused by an actor"),
        (.resumed, "resumed"),
        (.ended(.finished), "ended (finished)"),
        (.ended(.stopped), "ended (stopped)"),
        (.ended(.questStopped), "ended (quest stopped)"),
        (.ended(.interrupted), "ended (interrupted by another scene)"),
        (.ended(.actorBehavior), "ended (ended by an actor)"),
        (.actionStarted(4), "action 4 started"),
        (.actionCompleted(4), "action 4 done"),
        (.voiceLoading(1), "action 1: voice file loading"),
        (.packageDone(2), "action 2: package done"),
        (.noLine(3), "action 3: no line passed"),
        (.emptyAlias(5), "action 5: actor alias empty"),
        (.actorUnavailable(6), "action 6: actor dead or busy"),
        (.unsupportedAction(7, type: 9), "action 7: type 9 not run")
    ])
    func eachStepReadsAsASentence(step: SceneStep, text: String) {
        #expect(SceneCore.text(step: step) == text)
    }

    @Test func aPackageStepNamesItsActor() {
        let actor = DialogueRuntimeFixture.speakerKey
        #expect(
            SceneCore.text(step: .packageStarted(1, actor: actor))
                == "action 1: \(actor) runs its package"
        )
    }

    @Test func aLineNamesSpeakerInfoTopicAndSeconds() {
        let line = SceneLine(
            speaker: DialogueRuntimeFixture.speakerKey,
            topic: FormID(DialogueRuntimeFixture.ordinaryTopic),
            info: FormID(DialogueRuntimeFixture.ordinaryInfo),
            seconds: 2.5
        )
        let expected = "\(line.speaker) says \(line.info) in topic \(line.topic) for 2.5 s"
        #expect(SceneCore.text(step: .line(line)) == expected)
    }

    @Test func anEventNamesItsSceneByEditorIDOrFormID() throws {
        let scene = try SceneFixture.scene()
        let catalog = SceneCatalog(scenes: [scene])
        let known = SceneEvent(scene: scene.formID, step: .began)
        #expect(SceneCore.text(known, catalog: catalog) == "TestScene: began")
        let unknown = SceneEvent(scene: FormID(0x77), step: .repeated)
        #expect(SceneCore.text(unknown, catalog: catalog) == "00000077: repeated")
    }

    @Test func thePlayingRowCountsPhasesFromOne() throws {
        let store = WorldStateStore()
        let scene = try SceneFixture.scene()
        _ = try SceneFixture.runtime(store: store, scene: scene).start(scene.formID)
        let state = try #require(store.component(SceneRuntimeState.self, for: scene.key))
        let row = SceneCore.playingRow(scene, state: state)
        #expect(row.editorID == "TestScene")
        #expect(row.phase == 1)
        #expect(row.phaseCount == scene.scene.phases.count)
        #expect(row.phaseName == "Greet")
        #expect(row.runningActions == [0])
    }
}
