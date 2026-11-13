// A scene's begin fragment goes to the dispatcher the runtime holds. The scene's
// VMAD is synthetic: no script, then the SCEN fragment tail.

import Foundation
@testable import OpenSkyDialogue
@testable import OpenSkyDialogueInterface
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyWorldState
import Testing

@MainActor
final class RecordingSceneFragments: SceneFragmentDispatching {
    private(set) var calls: [(scriptName: String, functionName: String)] = []

    func runSceneFragment(
        of _: Scene, key _: ReferenceKey, scriptName: String, functionName: String
    ) -> Bool {
        calls.append((scriptName, functionName))
        return true
    }
}

@MainActor
struct SceneFragmentDispatchTests {
    static let sceneID: UInt32 = 0x4010

    /// SCEN fragment tail: int8 version, uint8 flags (bit 0 begin), file name, then
    /// per set bit one unused byte, script name, and function name, then uint16 phase count.
    static func beginFragmentVMAD() -> Data {
        var tail = Data([2, 0x01]) + wstring("SF_Test") + Data([1])
        tail += wstring("SF_Test") + wstring("Fragment_Begin")
        tail.appendUInt16(0)
        return VMADFixture.payload(scripts: [], tail: tail)
    }

    static func wstring(_ value: String) -> Data {
        var data = Data()
        data.appendUInt16(UInt16(value.utf8.count))
        return data + Data(value.utf8)
    }

    static func scene() throws -> CatalogScene {
        let fields: [(String, Data)] = [
            ("EDID", ESMFixture.zstring("FragmentScene")),
            ("VMAD", beginFragmentVMAD()),
            ("HNAM", Data()), ("NAM0", ESMFixture.zstring("Wait")), ("NEXT", Data()),
            ("CTDA", SceneFixture.condition(gateEquals: 1)), ("NEXT", Data()), ("HNAM", Data()),
            ("PNAM", ESMFixture.u32(DialogueRuntimeFixture.runningQuest))
        ]
        let record = try Scene(record: ESMFixture.record("SCEN", formID: sceneID, fields: fields))
        return CatalogScene(
            formID: FormID(sceneID),
            key: .plugin(name: DialogueFixture.pluginName, objectID: sceneID),
            scene: record
        )
    }

    @Test func theBeginFragmentGoesToTheDispatcher() throws {
        let scene = try Self.scene()
        let fragments = RecordingSceneFragments()
        let runtime = try SceneFixture.runtime(
            store: WorldStateStore(), scene: scene, fragments: fragments
        )
        let events = try runtime.start(scene.formID)
        #expect(fragments.calls.map(\.functionName) == ["Fragment_Begin"])
        #expect(fragments.calls.map(\.scriptName) == ["SF_Test"])
        #expect(events.contains { $0.step == .fragment("Fragment_Begin") })
    }
}
