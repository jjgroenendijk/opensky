// Phase completion conditions: a phase that has them ends only when they pass
// (<https://ck.uesp.net/wiki/Scenes_Tab>, "End on conditions").

import Foundation
@testable import OpenSkyDialogue
@testable import OpenSkyDialogueInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorldState
import Testing

@MainActor
struct SceneCompletionConditionTests {
    private let id = FormID(SceneFixture.sceneID)

    private func steps(_ events: [SceneEvent]) -> [SceneStep] {
        events.map(\.step)
    }

    /// Passing completion conditions end a phase while its timer still runs.
    @Test func completionConditionsEndAPhaseEarly() throws {
        let store = WorldStateStore()
        let scene = try SceneFixture.scene(waitEndsOnGate: true)
        try SceneFixture.runtime(store: store, scene: scene).start(id)
        let events = try SceneFixture.runtime(store: store, scene: scene, gate: 1, now: 3).tick()
        #expect(steps(events).contains(.phaseCompleted(1, byConditions: true)))
        #expect(steps(events).last == .ended(.finished))
    }

    /// A phase with completion conditions waits for them after its timer is done,
    /// as the Creation Kit's "End on conditions" choice does.
    @Test func aDoneTimerDoesNotEndAPhaseWithCompletionConditions() throws {
        let store = WorldStateStore()
        let scene = try SceneFixture.scene(waitEndsOnGate: true)
        try SceneFixture.runtime(store: store, scene: scene).start(id)
        _ = try SceneFixture.runtime(store: store, scene: scene, now: 3).tick()
        let waiting = try SceneFixture.runtime(store: store, scene: scene, now: 30).tick()
        #expect(!steps(waiting).contains {
            if case .phaseCompleted = $0 {
                true
            } else {
                false
            }
        })
        #expect(store.component(SceneRuntimeState.self, for: scene.key)?.phase == 1)

        let events = try SceneFixture.runtime(store: store, scene: scene, gate: 1, now: 31).tick()
        #expect(steps(events).contains(.phaseCompleted(1, byConditions: true)))
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
}
