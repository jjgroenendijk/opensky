// A scene flagged "Repeat while true" plays again at once, one run per tick
// (docs/engine/scenes.md).

import Foundation
@testable import OpenSkyDialogue
import OpenSkyDialogueFixtures
import OpenSkyDialogueInterface
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

    @Test func aRepeatingScenePlaysAgainOnTheNextTick() throws {
        let store = WorldStateStore()
        let scene = try Self.repeatScene()
        let started = try SceneFixture.runtime(store: store, scene: scene)
            .start(scene.formID).map(\.step)
        #expect(started.count { $0 == .phaseStarted(0) } == 1)
        #expect(started.last == .repeated)
        let again = try SceneFixture.runtime(store: store, scene: scene, now: 0.1)
            .tick().map(\.step)
        #expect(again.count { $0 == .phaseStarted(0) } == 1)
        #expect(again.last == .repeated)
    }
}
