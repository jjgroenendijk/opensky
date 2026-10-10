// Scene playback over `SceneFixture`: phases in order, a line said by the
// alias actor, a timer that holds its phase, conditions that end or skip a
// phase, and stops by request and by quest.

import FeaturesTesting
import Foundation
@testable import OpenSkyDialogue
import OpenSkyDialogueFixtures
@testable import OpenSkyDialogueInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorldState
import Testing

@MainActor
struct SceneRuntimeTests {
    private let id = FormID(SceneFixture.sceneID)

    private func steps(_ events: [SceneEvent]) -> [SceneStep] {
        events.map(\.step)
    }

    /// Phase 1 says the line and waits for it; phase 2 waits for the timer;
    /// phase 3 fails its start conditions and is skipped; the scene ends.
    @Test func playsPhasesInOrder() throws {
        let store = WorldStateStore()
        let scene = try SceneFixture.scene()
        let line = SceneLine(
            speaker: DialogueRuntimeFixture.speakerKey,
            topic: FormID(DialogueRuntimeFixture.ordinaryTopic),
            info: FormID(DialogueRuntimeFixture.ordinaryInfo)
        )
        let started = try SceneFixture.runtime(store: store, scene: scene).start(id)
        #expect(steps(started) == [.began, .phaseStarted(0), .actionStarted(0), .line(line)])
        #expect(store.component(SceneRuntimeState.self, for: scene.key)?.isRunning(0) == true)

        let secondPhase = try SceneFixture.runtime(store: store, scene: scene, now: 3).tick()
        #expect(steps(secondPhase) == [
            .actionCompleted(0), .phaseCompleted(0, byConditions: false),
            .phaseStarted(1), .actionStarted(1)
        ])
        #expect(try SceneFixture.runtime(store: store, scene: scene, now: 7).tick().isEmpty)

        let end = try SceneFixture.runtime(store: store, scene: scene, now: 8).tick()
        #expect(steps(end) == [
            .actionCompleted(1), .phaseCompleted(1, byConditions: false),
            .phaseSkipped(2), .ended(.finished)
        ])
        #expect(store.component(SceneRuntimeState.self, for: scene.key) == nil)
        let dialogue = try SceneFixture.runtime(store: store, scene: scene).dialogue
        #expect(dialogue.saidState(of: FormID(DialogueRuntimeFixture.ordinaryInfo)).saidCount == 1)
    }

    /// Passing completion conditions end a phase while its timer still runs.
    @Test func completionConditionsEndAPhaseEarly() throws {
        let store = WorldStateStore()
        let scene = try SceneFixture.scene()
        try SceneFixture.runtime(store: store, scene: scene).start(id)
        let events = try SceneFixture.runtime(store: store, scene: scene, gate: 1, now: 3).tick()
        #expect(steps(events).contains(.phaseCompleted(1, byConditions: true)))
        #expect(steps(events).last == .ended(.finished))
    }

    /// A phase with end conditions and no actions waits for the conditions.
    @Test func aPhaseWithOnlyEndConditionsWaitsForThem() throws {
        let store = WorldStateStore()
        let scene = try SceneFixture.waitScene()
        let started = try SceneFixture.runtime(store: store, scene: scene).start(scene.formID)
        #expect(steps(started) == [.began, .phaseStarted(0)])
        let events = try SceneFixture.runtime(store: store, scene: scene, gate: 1, now: 1).tick()
        #expect(steps(events) == [.phaseCompleted(0, byConditions: true), .ended(.finished)])
    }

    /// A phase whose start conditions pass runs; one with no actions ends at once.
    @Test func startConditionsLetAPhaseRun() throws {
        let store = WorldStateStore()
        let scene = try SceneFixture.scene()
        try SceneFixture.runtime(store: store, scene: scene, gate: 2).start(id)
        _ = try SceneFixture.runtime(store: store, scene: scene, gate: 2, now: 3).tick()
        let events = try SceneFixture.runtime(store: store, scene: scene, gate: 2, now: 8).tick()
        #expect(steps(events).suffix(3) == [
            .phaseStarted(2), .phaseCompleted(2, byConditions: false), .ended(.finished)
        ])
    }

    /// The state survives a store snapshot, and playback goes on from it.
    @Test func aPlayingSceneSurvivesARestore() throws {
        let store = WorldStateStore()
        let scene = try SceneFixture.scene()
        try SceneFixture.runtime(store: store, scene: scene).start(id)
        _ = try SceneFixture.runtime(store: store, scene: scene, now: 3).tick()
        let restored = WorldStateStore()
        restored.restore(from: store.snapshot())
        #expect(restored.component(SceneRuntimeState.self, for: scene.key)
            == store.component(SceneRuntimeState.self, for: scene.key))
        let events = try SceneFixture.runtime(store: restored, scene: scene, now: 8).tick()
        #expect(steps(events).last == .ended(.finished))
    }

    @Test func stopEndsTheScene() throws {
        let store = WorldStateStore()
        let scene = try SceneFixture.scene()
        let runtime = try SceneFixture.runtime(store: store, scene: scene)
        try runtime.start(id)
        #expect(steps(runtime.stop(id)) == [.ended(.stopped)])
        #expect(!runtime.isPlaying(id))
        #expect(runtime.stop(id).isEmpty)
    }

    /// The coordinator passes the scenes it knows play, so a tick reads no other scene.
    @Test func aTickOfNamedScenesAdvancesOnlyThose() throws {
        let store = WorldStateStore()
        let scene = try SceneFixture.scene()
        try SceneFixture.runtime(store: store, scene: scene).start(id)

        let runtime = try SceneFixture.runtime(store: store, scene: scene, now: 3)
        #expect(runtime.tick(scenes: []).isEmpty)
        #expect(runtime.tick(scenes: [FormID(0xDEAD)]).isEmpty)
        let named = try SceneFixture.runtime(store: store, scene: scene, now: 3).tick(scenes: [id])
        #expect(steps(named).contains(.phaseStarted(1)))
    }

    @Test func aSceneEndsWhenItsQuestStops() throws {
        let store = WorldStateStore()
        let scene = try SceneFixture.scene()
        try SceneFixture.runtime(store: store, scene: scene).start(id)
        let events = try SceneFixture.runtime(store: store, scene: scene, questStopped: true).tick()
        #expect(steps(events) == [.ended(.questStopped)])
    }

    @Test func aSceneNeedsItsQuestRunning() throws {
        let scene = try SceneFixture.scene(quest: DialogueRuntimeFixture.dormantQuest)
        let runtime = try SceneFixture.runtime(store: WorldStateStore(), scene: scene)
        #expect(throws: SceneError.questNotRunning(FormID(DialogueRuntimeFixture.dormantQuest))) {
            try runtime.start(id)
        }
    }

    /// An empty actor alias counts as a dead actor: its action is done at once.
    @Test func anEmptyAliasCompletesItsActionAtOnce() throws {
        let scene = try SceneFixture.scene()
        let runtime = try SceneFixture.runtime(
            store: WorldStateStore(),
            scene: scene,
            filled: false
        )
        let events = try runtime.start(id)
        #expect(steps(events).contains(.emptyAlias(0)))
        #expect(steps(events).contains(.phaseStarted(1)))
    }

    @Test func aQuestStartBeginsFlaggedScenes() throws {
        let scene = try SceneFixture.scene(flags: 0x01)
        let runtime = try SceneFixture.runtime(store: WorldStateStore(), scene: scene)
        let events = runtime.questDidStart(FormID(DialogueRuntimeFixture.runningQuest))
        #expect(steps(events).first == .began)
        #expect(runtime.isPlaying(id))
    }

    /// A tick that changes nothing writes nothing, so cells do not rebuild.
    @Test func aWaitingTickDoesNotWriteTheStore() throws {
        let store = WorldStateStore()
        let scene = try SceneFixture.scene()
        try SceneFixture.runtime(store: store, scene: scene).start(id)
        let sequence = store.nextJournalSequence
        _ = try SceneFixture.runtime(store: store, scene: scene, now: 1).tick()
        #expect(store.nextJournalSequence == sequence)
    }

    @Test func lineDurationGrowsWithText() {
        #expect(SceneCore.lineDuration(texts: []) == SceneRuntime.defaultLineDuration)
        #expect(SceneCore.lineDuration(texts: ["Hi"]) == 1.5)
        #expect(SceneCore.lineDuration(texts: [String(repeating: "a", count: 30), nil]) == 5)
    }

    // MARK: - Package actions and line timing

    private let walk = FormID(SceneFixture.packageSceneID)

    /// The actor runs the package until it is done; then the lines play.
    @Test func aPackageActionRunsUntilItsPackageIsDone() throws {
        let store = WorldStateStore()
        let scene = try SceneFixture.packageScene()
        let host = FakeSceneHost()
        let speaker = DialogueRuntimeFixture.speakerKey
        let started = try SceneFixture.runtime(store: store, scene: scene, host: host).start(walk)
        #expect(steps(started).contains(.packageStarted(0, actor: speaker)))
        #expect(!steps(started)
            .contains {
                if case .unsupportedAction = $0 {
                    true
                } else {
                    false
                }
            })
        #expect(host.running[speaker] == [FormID(SceneFixture.walkPackage)])
        #expect(try SceneFixture.runtime(store: store, scene: scene, now: 30, host: host)
            .tick().isEmpty)

        host.packageDone = true
        let events = try SceneFixture.runtime(store: store, scene: scene, now: 31, host: host)
            .tick()
        #expect(Array(steps(events).prefix(4)) == [
            .packageDone(0), .actionCompleted(0), .phaseCompleted(0, byConditions: false),
            .phaseStarted(1)
        ])
        #expect(host.running[speaker] == nil)
        #expect(host.released == [speaker])
    }

    /// Stopping a scene hands the package actor back to its schedule.
    @Test func stoppingASceneReleasesItsPackageActor() throws {
        let store = WorldStateStore()
        let scene = try SceneFixture.packageScene()
        let host = FakeSceneHost()
        let runtime = try SceneFixture.runtime(store: store, scene: scene, host: host)
        try runtime.start(walk)
        runtime.stop(walk)
        #expect(host.released == [DialogueRuntimeFixture.speakerKey])
    }

    /// A line waits for its voice file, then lasts as long as the file. The next
    /// phase's line starts in the tick the first one ends.
    @Test func linesLastTheirVoiceFileWithNoGap() throws {
        let store = WorldStateStore()
        let scene = try SceneFixture.packageScene()
        let host = FakeSceneHost()
        let pending = ScenePendingLines()
        func tick(_ now: Double) throws -> [SceneStep] {
            try steps(SceneFixture.runtime(
                store: store, scene: scene, now: now, host: host, pendingLines: pending
            ).tick())
        }
        host.packageDone = true
        host.lineSeconds = nil
        let started = try steps(SceneFixture.runtime(
            store: store, scene: scene, host: host, pendingLines: pending
        ).start(walk))
        #expect(started.contains(.voiceLoading(1)))
        #expect(try tick(10).isEmpty)

        host.lineSeconds = 4
        #expect(try lines(tick(20)) == [4])
        #expect(pending.isEmpty)
        #expect(try tick(23.9).isEmpty)
        let next = try tick(24)
        #expect(next.prefix(3) == [
            .actionCompleted(1),
            .phaseCompleted(1, byConditions: false),
            .phaseStarted(2)
        ])
        #expect(lines(next) == [4])
        #expect(try tick(28).suffix(2) == [
            .phaseCompleted(2, byConditions: false),
            .ended(.finished)
        ])
    }

    private func lines(_ steps: [SceneStep]) -> [Float] {
        steps.compactMap {
            if case let .line(line) = $0 {
                line.seconds
            } else {
                nil
            }
        }
    }
}
