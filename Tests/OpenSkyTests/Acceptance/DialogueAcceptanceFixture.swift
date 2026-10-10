// The dialogue gate's world: one speaker, four topics, one quest, and its
// result script. `questTopic` is say-once and sets stage 10; `stageTopic` needs
// `GetStageDone(quest, 10)`, so its appearance proves the result ran;
// `goodbyeTopic` ends the talk; the HELO greeting is say-once. Keyed under
// `PapyrusWorldFixture.pluginName` so INFO keys match Papyrus instance keys.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsPEX
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import OpenSkyScriptingFixtures
@testable import OpenSkyWorldState

enum DialogueAcceptanceFixture {
    static let greetingTopic: UInt32 = 0x0000_1700
    static let questTopic: UInt32 = 0x0000_1701
    static let stageTopic: UInt32 = 0x0000_1702
    static let goodbyeTopic: UInt32 = 0x0000_1703

    static let greetingInfo: UInt32 = 0x0000_1710
    static let questInfo: UInt32 = 0x0000_1711
    static let stageInfo: UInt32 = 0x0000_1712
    static let goodbyeInfo: UInt32 = 0x0000_1713

    /// Generated result script of `questInfo`, named the way the Creation Kit
    /// names one for a record with no editor ID.
    static let resultScript = "TIF__00001711"
    static let beginFunction = "Fragment_0"
    static let endFunction = "Fragment_1"

    /// The speaker. A placed ACHR the crosshair can pick up, and the identity
    /// said-state, the camera and the face morphs are all filed under.
    static let speakerObjectID: UInt32 = 0x0000_1720
    static let speakerBase: UInt32 = 0x0000_1721
    static let speakerName = "OpenSky Test Speaker"

    static var speakerKey: ReferenceKey {
        .plugin(name: PapyrusWorldFixture.pluginName, objectID: speakerObjectID)
    }

    static func infoKey(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: PapyrusWorldFixture.pluginName, objectID: objectID)
    }

    // MARK: - Stores

    static func dialogueStore() throws -> DialogueStore {
        try DialogueStore(
            file: ESMFile(data: DialogueFixture.plugin(dialogueChildren: topics())),
            pluginName: PapyrusWorldFixture.pluginName
        )
    }

    /// A Papyrus session over the probe quest and the generated result script,
    /// sharing the store the dialogue layer writes said-state into so one save
    /// carries both.
    @MainActor
    static func session(worldState: WorldStateStore) throws -> PapyrusWorldFixture.Session {
        try PapyrusQuestFixture.session(
            quest: PapyrusQuestFixture.quest(),
            objects: PapyrusQuestFixture.objects([resultScriptObject()]),
            worldState: worldState
        )
    }

    // MARK: - Records

    private static func topics() -> Data {
        greeting() + quest() + stageGated() + goodbye()
    }

    private static func greeting() -> Data {
        DialogueFixture.topicRecord(
            formID: greetingTopic,
            fields: DialogueFixture.editorID("DialogueGreeting")
                // Category 7, miscellaneous: a greeting is not a topic the
                // player picks.
                + DialogueFixture.topicData(category: 7)
                + DialogueFixture.subtype("HELO")
                + DialogueFixture.priority(50)
                + DialogueFixture.word("QNAM", PapyrusQuestFixture.questObjectID)
        )
            + DialogueFixture.topicChildren(
                parent: greetingTopic,
                infos: DialogueFixture.infoRecord(
                    formID: greetingInfo,
                    fields: DialogueFixture.infoData(flags: sayOnceFlag)
                        + DialogueFixture.response()
                        + DialogueFixture.inlineText("NAM1", "Well met, traveller.")
                )
            )
    }

    private static func quest() -> Data {
        DialogueFixture.topicRecord(
            formID: questTopic,
            fields: DialogueFixture.editorID("DialogueQuestTopic")
                + DialogueFixture.topicData(category: 0)
                + DialogueFixture.subtype("CUST")
                + DialogueFixture.priority(90)
                + DialogueFixture.inlineText("FULL", "I will help you.")
                + DialogueFixture.word("QNAM", PapyrusQuestFixture.questObjectID)
        )
            + DialogueFixture.topicChildren(
                parent: questTopic,
                infos: DialogueFixture.infoRecord(
                    formID: questInfo,
                    fields: DialogueFixture.infoData(flags: sayOnceFlag)
                        + DialogueFixture.vmad(
                            scripts: [VMADFixture.Script(resultScript, properties: [
                                VMADFixture.Property(
                                    "MyQuest",
                                    .object(VMADFixture.object(
                                        PapyrusQuestFixture.questObjectID
                                    ))
                                )
                            ])],
                            tail: DialogueFixture.infoFragmentTail(
                                fileName: resultScript,
                                begin: beginFunction,
                                end: endFunction
                            )
                        )
                        + DialogueFixture.response()
                        + DialogueFixture.inlineText("NAM1", "Then it is begun.")
                )
            )
    }

    private static func stageGated() -> Data {
        DialogueFixture.topicRecord(
            formID: stageTopic,
            fields: DialogueFixture.editorID("DialogueStageTopic")
                + DialogueFixture.topicData(category: 0)
                + DialogueFixture.subtype("CUST")
                + DialogueFixture.priority(80)
                + DialogueFixture.inlineText("FULL", "About what you asked of me.")
                + DialogueFixture.word("QNAM", PapyrusQuestFixture.questObjectID)
        )
            + DialogueFixture.topicChildren(
                parent: stageTopic,
                infos: DialogueFixture.infoRecord(
                    formID: stageInfo,
                    fields: DialogueFixture.infoData()
                        + stageDoneCondition()
                        + DialogueFixture.response()
                        + DialogueFixture.inlineText("NAM1", "You have made a start.")
                )
            )
    }

    private static func goodbye() -> Data {
        DialogueFixture.topicRecord(
            formID: goodbyeTopic,
            fields: DialogueFixture.editorID("DialogueGoodbye")
                + DialogueFixture.topicData(category: 0)
                + DialogueFixture.subtype("CUST")
                + DialogueFixture.priority(10)
                + DialogueFixture.inlineText("FULL", "Farewell.")
                + DialogueFixture.word("QNAM", PapyrusQuestFixture.questObjectID)
        )
            + DialogueFixture.topicChildren(
                parent: goodbyeTopic,
                infos: DialogueFixture.infoRecord(
                    formID: goodbyeInfo,
                    fields: DialogueFixture.infoData(flags: goodbyeFlag)
                        + DialogueFixture.response()
                        + DialogueFixture.inlineText("NAM1", "Safe roads.")
                )
            )
    }

    /// `GetStageDone(probe quest, 10) == 1`, function index 59.
    private static func stageDoneCondition() -> Data {
        DialogueFixture.condition(
            functionIndex: 59,
            comparisonValue: 1,
            parameter1: PapyrusQuestFixture.questObjectID,
            parameter2: UInt32(PapyrusQuestFixture.fragmentStage)
        )
    }

    /// INFO ENAM flag bits: goodbye is bit 0, say once is bit 2.
    private static let goodbyeFlag: UInt16 = 1 << 0
    private static let sayOnceFlag: UInt16 = 1 << 2

    // MARK: - The result script

    /// The generated result script, shaped like a compiled TIF_ file: an object
    /// holding a `Quest` property whose begin fragment sets a stage on it, and
    /// an end fragment that only records that it ran.
    private static func resultScriptObject() -> PexObject {
        PexFixture.runtimeObject(
            name: resultScript,
            variables: [PexVariable(
                name: "::MyQuest_var", typeName: "Quest",
                userFlags: 0, initialValue: .null
            )],
            properties: [PexProperty(
                name: "MyQuest",
                typeName: "Quest",
                documentation: "",
                userFlags: 0,
                flags: [.readable, .writable, .automatic],
                automaticVariableName: "::MyQuest_var",
                readHandler: nil,
                writeHandler: nil
            )],
            states: [PapyrusTestSupport.state(functions: [
                (beginFunction, setStageBody(PapyrusQuestFixture.fragmentStage)),
                (endFunction, PapyrusWorldFixture.probeBody(note: "m17.info.end")),
                ("OnInit", PapyrusWorldFixture.probeBody(note: "m17.info.oninit"))
            ])]
        )
    }

    /// `MyQuest.SetStage(stage)`, the call a generated result script makes.
    private static func setStageBody(_ stage: UInt16) -> PexFunction {
        PexFixture.runtimeFunction(instructions: [
            PapyrusTestSupport.instruction(
                .callMethod,
                .identifier("SetStage"),
                .identifier("::MyQuest_var"),
                .identifier("::nonevar"),
                .integer(1),
                .integer(Int32(stage))
            )
        ])
    }
}
