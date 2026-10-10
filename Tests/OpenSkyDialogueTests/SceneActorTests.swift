// Scene actors: one scene at a time per actor, `ForceStart()`, interruptible
// scenes, and the actor behaviour flags that pause or end a scene.

import Foundation
@testable import OpenSkyDialogue
import OpenSkyDialogueFixtures
@testable import OpenSkyDialogueInterface
import OpenSkyEngineTesting
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyQuestsInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct SceneActorTests {
    private let speaker = DialogueRuntimeFixture.speakerKey

    /// One phase with a 4 second timer, and the speaker's alias as its one actor.
    private func timerScene(
        _ id: UInt32, sceneFlags: UInt32 = 0, actorFlags: UInt32 = 0, behavior: UInt32 = 0
    ) throws -> CatalogScene {
        let fields: [(String, Data)] = [
            ("EDID", ESMFixture.zstring("Timer\(id)")), ("FNAM", ESMFixture.u32(sceneFlags)),
            ("HNAM", Data()), ("NEXT", Data()), ("NEXT", Data()), ("HNAM", Data()),
            ("ALID", ESMFixture.i32(0)), ("LNAM", ESMFixture.u32(actorFlags)),
            ("DNAM", ESMFixture.u32(behavior)),
            ("ANAM", ESMFixture.u16(2)), ("ALID", ESMFixture.i32(0)), ("INAM", ESMFixture.u32(1)),
            ("SNAM", ESMFixture.u32(0)), ("ENAM", ESMFixture.u32(0)),
            ("SNAM", ESMFixture.f32(4)), ("ANAM", Data()),
            ("PNAM", ESMFixture.u32(DialogueRuntimeFixture.runningQuest))
        ]
        let record = try Scene(record: ESMFixture.record("SCEN", formID: id, fields: fields))
        return CatalogScene(
            formID: FormID(id), key: .plugin(name: DialogueFixture.pluginName, objectID: id),
            scene: record
        )
    }

    private func steps(_ events: [SceneEvent], of scene: CatalogScene) -> [SceneStep] {
        events.filter { $0.scene == scene.formID }.map(\.step)
    }

    @Test func behaviorBitsDecode() throws {
        let scene = try timerScene(0x4100, actorFlags: 0x02, behavior: 26)
        let actor = try #require(scene.scene.actors.first)
        #expect(actor.isOptional)
        #expect(actor.behavior == [.deathEnd, .combatEnd, .dialoguePause])
    }

    /// A second scene waits before its first phase while the first holds the actor.
    @Test func aSceneWaitsForAnActorInAnotherScene() throws {
        let store = WorldStateStore()
        let first = try timerScene(0x4100)
        let second = try timerScene(0x4101)
        let runtime = try SceneFixture.runtime(store: store, scene: first, others: [second])
        try runtime.start(first.formID)
        let waiting = try runtime.start(second.formID)
        #expect(steps(waiting, of: second) == [.began, .waitingForActors])

        let later = try SceneFixture.runtime(
            store: store, scene: first, now: 5, others: [second]
        ).tick()
        #expect(steps(later, of: first).last == .ended(.finished))
        #expect(steps(later, of: second).contains(.phaseStarted(0)))
    }

    /// An optional actor held elsewhere does not hold the scene back.
    @Test func anOptionalActorDoesNotWait() throws {
        let store = WorldStateStore()
        let first = try timerScene(0x4100)
        let second = try timerScene(0x4101, actorFlags: 0x02)
        let runtime = try SceneFixture.runtime(store: store, scene: first, others: [second])
        try runtime.start(first.formID)
        #expect(try steps(runtime.start(second.formID), of: second).contains(.phaseStarted(0)))
    }

    @Test func anInterruptibleSceneGivesWay() throws {
        let store = WorldStateStore()
        let first = try timerScene(0x4100, sceneFlags: 0x10)
        let second = try timerScene(0x4101)
        let runtime = try SceneFixture.runtime(store: store, scene: first, others: [second])
        try runtime.start(first.formID)
        let events = try runtime.start(second.formID)
        #expect(steps(events, of: first) == [.ended(.interrupted)])
        #expect(steps(events, of: second).contains(.phaseStarted(0)))
    }

    @Test func forceStartStopsScenesWithTheSameActors() throws {
        let store = WorldStateStore()
        let first = try timerScene(0x4100)
        let second = try timerScene(0x4101)
        let runtime = try SceneFixture.runtime(store: store, scene: first, others: [second])
        try runtime.start(first.formID)
        let events = try runtime.forceStart(second.formID)
        #expect(steps(events, of: first) == [.ended(.interrupted)])
        #expect(runtime.isPlaying(second.formID))
        #expect(!runtime.isPlaying(first.formID))
    }

    /// Death end stops a scene even before it starts its first phase.
    @Test func deathEndsTheScene() throws {
        let host = FakeSceneHost()
        host.statuses[speaker] = .dead
        let scene = try timerScene(0x4100, behavior: 0x02)
        let events = try SceneFixture.runtime(store: WorldStateStore(), scene: scene, host: host)
            .start(scene.formID)
        #expect(steps(events, of: scene) == [.began, .ended(.actorBehavior)])
    }

    /// Combat pauses the timer; after the fight it keeps the seconds it had left.
    @Test func combatPausesAndTheTimerResumes() throws {
        let store = WorldStateStore()
        let host = FakeSceneHost()
        let scene = try timerScene(0x4100, behavior: 0x04)
        try SceneFixture.runtime(store: store, scene: scene, host: host).start(scene.formID)
        host.statuses[speaker] = .inCombat
        let paused = try SceneFixture.runtime(store: store, scene: scene, now: 1, host: host).tick()
        #expect(steps(paused, of: scene) == [.paused])
        #expect(try SceneFixture.runtime(store: store, scene: scene, now: 9, host: host)
            .tick().isEmpty)
        host.statuses[speaker] = []
        let resumed = try SceneFixture.runtime(store: store, scene: scene, now: 11, host: host)
            .tick()
        #expect(steps(resumed, of: scene) == [.resumed])
        let done = try SceneFixture.runtime(store: store, scene: scene, now: 14, host: host).tick()
        #expect(steps(done, of: scene).last == .ended(.finished))
    }

    /// A dead actor's action is done at once when no flag ends the scene.
    @Test func aDeadActorsActionIsDone() throws {
        let host = FakeSceneHost()
        host.statuses[speaker] = .dead
        let scene = try SceneFixture.scene()
        let events = try SceneFixture.runtime(store: WorldStateStore(), scene: scene, host: host)
            .start(scene.formID)
        #expect(steps(events, of: scene).contains(.actorUnavailable(0)))
    }
}
