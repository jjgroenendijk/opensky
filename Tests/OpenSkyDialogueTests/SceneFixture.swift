// A three-phase scene over the dialogue fixture world: a line, a timer that a
// global can cut short, and a phase only a global value lets start.

import EngineTesting
import FeaturesTesting
import FormatsTesting
import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyDialogue
import OpenSkyDialogueFixtures
@testable import OpenSkyDialogueInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyQuestsInterface
@testable import OpenSkyWorldState
import Testing

enum SceneFixture {
    static let sceneID: UInt32 = 0x4000
    static let gate: UInt32 = 0x0900
    static let timerSeconds: Float = 5

    static func condition(gateEquals value: Float) -> Data {
        DialogueFixture.condition(functionIndex: 74, comparisonValue: value, parameter1: gate)
            .dropFirst(6)
    }

    static func scene(
        flags: UInt32 = 0,
        quest: UInt32 = DialogueRuntimeFixture.runningQuest
    ) throws -> CatalogScene {
        let fields: [(String, Data)] = [
            ("EDID", ESMFixture.zstring("TestScene")), ("FNAM", ESMFixture.u32(flags)),
            ("HNAM", Data()), ("NAM0", ESMFixture.zstring("Greet")), ("NEXT", Data()),
            ("NEXT", Data()), ("HNAM", Data()),
            ("HNAM", Data()), ("NAM0", ESMFixture.zstring("Wait")), ("NEXT", Data()),
            ("CTDA", condition(gateEquals: 1)), ("NEXT", Data()), ("HNAM", Data()),
            ("HNAM", Data()), ("NAM0", ESMFixture.zstring("Gated")),
            ("CTDA", condition(gateEquals: 2)), ("NEXT", Data()), ("NEXT", Data()), (
                "HNAM",
                Data()
            ),
            ("ALID", ESMFixture.i32(0)),
            ("ANAM", ESMFixture.u16(0)), ("ALID", ESMFixture.i32(0)), ("INAM", ESMFixture.u32(1)),
            ("SNAM", ESMFixture.u32(0)), ("ENAM", ESMFixture.u32(0)),
            ("DATA", ESMFixture.u32(DialogueRuntimeFixture.ordinaryTopic)), ("ANAM", Data()),
            ("ANAM", ESMFixture.u16(2)), ("INAM", ESMFixture.u32(2)), ("SNAM", ESMFixture.u32(1)),
            ("ENAM", ESMFixture.u32(1)), ("SNAM", ESMFixture.f32(timerSeconds)), ("ANAM", Data()),
            ("PNAM", ESMFixture.u32(quest))
        ]
        let record = try Scene(record: ESMFixture.record("SCEN", formID: sceneID, fields: fields))
        return CatalogScene(
            formID: FormID(sceneID),
            key: .plugin(name: DialogueFixture.pluginName, objectID: sceneID),
            scene: record
        )
    }

    /// A runtime whose quest fills alias 0 with the speaker, unless `filled` is false.
    @MainActor
    static func runtime(
        store: WorldStateStore,
        scene: CatalogScene,
        gate value: Float = 0,
        now: Double = 0,
        filled: Bool = true,
        questStopped: Bool = false,
        host: FakeSceneHost? = nil,
        pendingLines: ScenePendingLines = ScenePendingLines()
    ) throws -> SceneRuntime {
        let quests = try DialogueRuntimeFixture.questStore()
        let questKey = try #require(quests.key(for: FormID(DialogueRuntimeFixture.runningQuest)))
        var context = try DialogueRuntimeFixture.context()
        let fills = filled
            ? [QuestAliasFill(aliasID: 0, reference: DialogueRuntimeFixture.speakerKey)] : []
        context.aliases = QuestAliasResolution(
            defaults: quests, tables: [questKey: QuestAliasState(fills: fills)]
        )
        context.globals = try GlobalResolution(defaults: GlobalFixture.store(GlobalFixture.record(
            formID: gate, editorID: "SceneGate", type: .float, value: value
        )))
        var overrides: [ReferenceKey: QuestRuntimeState] = [:]
        if questStopped, let quest = quests.quest(FormID(DialogueRuntimeFixture.runningQuest)) {
            overrides[questKey] = QuestRuntimeState.baseline(for: quest).stopping()
        }
        let dialogue = try DialogueRuntime(
            store: store,
            dialogue: DialogueRuntimeFixture.dialogueStore(),
            questStates: QuestResolution(defaults: quests, overrides: overrides),
            context: context,
            registry: .dialogueTests
        )
        return SceneRuntime(
            catalog: SceneCatalog(scenes: [scene]), dialogue: dialogue,
            host: host, pendingLines: pendingLines, now: now
        )
    }
}

extension SceneFixture {
    static let packageSceneID: UInt32 = 0x4001
    static let walkPackage: UInt32 = 0x5000

    /// Three phases. A package action holds phase 1. Phase 2 says the ordinary
    /// line, and phase 3 the scene line.
    static func packageScene() throws -> CatalogScene {
        func action(type: UInt16, index: UInt32, phase: UInt32, payload: [(String, Data)])
            -> [(String, Data)]
        {
            [
                ("ANAM", ESMFixture.u16(type)),
                ("ALID", ESMFixture.i32(0)),
                ("INAM", ESMFixture.u32(index)),
                ("SNAM", ESMFixture.u32(phase)),
                ("ENAM", ESMFixture.u32(phase))
            ] + payload + [("ANAM", Data())]
        }
        func phase(_ name: String) -> [(String, Data)] {
            [
                ("HNAM", Data()),
                ("NAM0", ESMFixture.zstring(name)),
                ("NEXT", Data()),
                ("NEXT", Data()),
                ("HNAM", Data())
            ]
        }
        let fields: [(String, Data)] = [("EDID", ESMFixture.zstring("WalkScene"))]
            + phase("Walk") + phase("Ask") + phase("Answer") + [("ALID", ESMFixture.i32(0))]
            + action(type: 1, index: 1, phase: 0, payload: [("PNAM", ESMFixture.u32(walkPackage))])
            + action(type: 0, index: 2, phase: 1, payload: [
                ("DATA", ESMFixture.u32(DialogueRuntimeFixture.ordinaryTopic))
            ])
            + action(type: 0, index: 3, phase: 2, payload: [
                ("DATA", ESMFixture.u32(DialogueRuntimeFixture.sceneTopic))
            ])
            + [("PNAM", ESMFixture.u32(DialogueRuntimeFixture.runningQuest))]
        let record = try Scene(
            record: ESMFixture.record("SCEN", formID: packageSceneID, fields: fields)
        )
        return CatalogScene(
            formID: FormID(packageSceneID),
            key: .plugin(name: DialogueFixture.pluginName, objectID: packageSceneID),
            scene: record
        )
    }
}

/// Answers the scene host from fixed values: line lengths, and a package that is
/// done once `packageDone` is set.
@MainActor
final class FakeSceneHost: SceneHost {
    /// Nil while the voice file "loads".
    var lineSeconds: Float? = 2
    var packageDone = false
    private(set) var running: [ReferenceKey: [FormID]] = [:]
    private(set) var released: [ReferenceKey] = []

    func lineDuration(of info: TopicInfo, speaker: ReferenceKey) -> Float? {
        lineSeconds
    }

    func stopQuest(_ quest: FormID) {}

    func runScenePackages(
        _ packages: [FormID], actor: ReferenceKey, owner: ScenePackageOwner
    ) -> ScenePackageState {
        running[actor] = packages
        return packageDone ? .done : .running
    }

    func releaseScenePackages(actor: ReferenceKey, owner: ScenePackageOwner) {
        running[actor] = nil
        released.append(actor)
    }
}
