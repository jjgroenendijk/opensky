// A scene flagged "Repeat while true" waits `fRandomSceneAgainMinTime` to `...MaxTime`
// before it plays again (docs/engine/scenes.md).

import Foundation
@testable import OpenSkyDialogue
import OpenSkyDialogueFixtures
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyWorldState
import Testing

@MainActor
struct SceneRepeatTests {
    private static let sceneID: UInt32 = 0x4010

    /// One empty phase; FNAM 0x08 repeats the scene while its (empty) conditions pass.
    private static func repeatScene() throws -> CatalogScene {
        let fields: [(String, Data)] = [
            ("EDID", ESMFixture.zstring("RepeatScene")),
            ("FNAM", ESMFixture.u32(0x08)),
            ("HNAM", Data()), ("NAM0", ESMFixture.zstring("Idle")), ("NEXT", Data()),
            ("NEXT", Data()), ("HNAM", Data()),
            ("PNAM", ESMFixture.u32(DialogueRuntimeFixture.runningQuest))
        ]
        let record = try Scene(record: ESMFixture.record("SCEN", formID: sceneID, fields: fields))
        return CatalogScene(
            formID: FormID(sceneID),
            key: .plugin(name: DialogueFixture.pluginName, objectID: sceneID),
            scene: record
        )
    }

    @Test func aRepeatingSceneWaitsBeforeItPlaysAgain() throws {
        let store = WorldStateStore()
        let pending = ScenePendingLines()
        let scene = try Self.repeatScene()
        func tick(_ now: Double) throws -> [SceneStep] {
            var runtime = try SceneFixture.runtime(
                store: store, scene: scene, now: now, pendingLines: pending
            )
            runtime.loopPause = { $0.lowerBound }
            runtime.repeatPause = 12 ... 20
            return try (now == 0 ? runtime.start(scene.formID) : runtime.tick()).map(\.step)
        }
        let started = try tick(0)
        #expect(started.last == .repeated)
        #expect(try tick(11).isEmpty)
        let again = try tick(12)
        #expect(again.contains(.phaseStarted(0)))
        #expect(again.last == .repeated)
        #expect(try tick(23).isEmpty)
    }
}
