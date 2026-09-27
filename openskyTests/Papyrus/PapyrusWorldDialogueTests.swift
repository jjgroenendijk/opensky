// Dialogue result scripts under the Papyrus world runtime (issue #426, roadmap
// item 17.2): the route a quest-stage result actually travels.
//
// This is the item's "result-to-setStage" bar, run end to end rather than
// asserted at a seam: a chosen response's TIF_ fragment calls `SetStage` on a
// `Quest`, the M13 native lands in `PapyrusWorldStateBridge`, and `QuestRuntime`
// records the stage. Nothing in the dialogue layer knows what a stage is, which
// is exactly the property the test exists to hold.
//
// Fixtures are synthetic, built in code by `PapyrusQuestFixture` and
// `DialogueFixture` — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct PapyrusWorldDialogueTests {
    private static let infoObjectID: UInt32 = 0x0000_2004
    private static let resultScript = "TIF__00002004"

    private var infoKey: ReferenceKey {
        .plugin(name: PapyrusWorldFixture.pluginName, objectID: Self.infoObjectID)
    }

    /// An INFO carrying a begin fragment that advances the probe quest and an
    /// end fragment that only records that it ran.
    ///
    /// The generated script is listed twice, exactly as shipped data lists it:
    /// once in the primary VMAD script list, where its `MyQuest` property names
    /// the quest the stage result advances, and once by name in the fragment
    /// tail.
    private func info() throws -> TopicInfo {
        try DialogueFixture.info(DialogueFixture.infoData() + Self.infoVMAD())
    }

    private static func infoVMAD() -> Data {
        DialogueFixture.vmad(
            scripts: [VMADFixture.Script(resultScript, properties: [
                VMADFixture.Property(
                    "MyQuest",
                    .object(VMADFixture.object(PapyrusQuestFixture.questObjectID))
                )
            ])],
            tail: DialogueFixture.infoFragmentTail(
                fileName: resultScript,
                begin: "Fragment_0",
                end: "Fragment_1"
            )
        )
    }

    /// The generated result script, shaped like a compiled TIF_ file: an object
    /// holding a `Quest` property whose begin fragment sets a stage on it.
    private func resultScriptObject() -> PexObject {
        PexFixture.runtimeObject(
            name: Self.resultScript,
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
                ("Fragment_0", Self.setStageOnPropertyBody(
                    PapyrusQuestFixture.fragmentStage
                )),
                ("Fragment_1", PapyrusWorldFixture.probeBody(note: "info.end")),
                ("OnInit", PapyrusWorldFixture.probeBody(note: "info.oninit"))
            ])]
        )
    }

    /// `MyQuest.SetStage(stage)`, the call a generated result script makes.
    private static func setStageOnPropertyBody(_ stage: UInt16) -> PexFunction {
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

    private func session() throws -> PapyrusWorldFixture.Session {
        try PapyrusQuestFixture.session(
            quest: PapyrusQuestFixture.quest(),
            objects: PapyrusQuestFixture.objects([resultScriptObject()])
        )
    }

    /// Dispatching a fragment instantiates the result script, runs it, and
    /// leaves the instance keyed by the INFO, persistent and in no cell —
    /// exactly the shape a quest's instances have.
    @Test func aResultFragmentInstantiatesItsScriptAndRuns() throws {
        let session = try session()
        PapyrusWorldFixture.drain(session.world)

        let names = try session.bridge.runTopicInfoFragments(
            of: info(), key: infoKey, phase: .end
        )
        #expect(names == ["Fragment_1"])
        #expect(session.world.dialogueInfoCount == 1)
        #expect(session.world.dialogueFragmentsQueued == 1)

        PapyrusWorldFixture.drain(session.world)
        #expect(session.dispatch.notes.contains("info.end"))
        // The instance is persistent and belongs to no cell, exactly as a
        // quest's does.
        let key = PapyrusInstanceKey(reference: infoKey, scriptName: Self.resultScript)
        #expect(session.world.persistentKeys.contains(key))
        #expect(session.world.attachedByCell.isEmpty)
    }

    /// Saying the same line twice runs on the instance the first saying
    /// created, so a result script keeps its variables between two sayings.
    @Test func asecondSayingReusesTheInstance() throws {
        let session = try session()
        let info = try info()
        session.bridge.runTopicInfoFragments(of: info, key: infoKey, phase: .end)
        PapyrusWorldFixture.drain(session.world)
        let created = session.world.instancesByKey.count

        session.bridge.runTopicInfoFragments(of: info, key: infoKey, phase: .end)
        PapyrusWorldFixture.drain(session.world)
        #expect(session.world.instancesByKey.count == created)
        #expect(session.dispatch.notes.filter { $0 == "info.end" }.count == 2)
        #expect(session.dispatch.notes.filter { $0 == "info.oninit" }.count == 1)
    }

    /// A response whose result script the library cannot resolve runs nothing,
    /// is counted, and is not a fault: the conversation goes on.
    @Test func amissingResultScriptIsCountedNotFaulted() throws {
        let session = try PapyrusQuestFixture.session(quest: PapyrusQuestFixture.quest())
        let names = try session.bridge.runTopicInfoFragments(
            of: info(), key: infoKey, phase: .begin
        )
        #expect(names.isEmpty)
        #expect(session.world.dialogueInfoCount == 0)
        #expect(session.world.runtime.tally.faultTotal == 0)
    }

    /// The item's minimum bar, driven from the dialogue layer rather than from
    /// the bridge: choosing a response runs its result, and the result sets a
    /// quest stage through `QuestRuntime`.
    @Test func choosingAResponseReachesSetStage() throws {
        let session = try session()
        PapyrusWorldFixture.drain(session.world)
        let runtime = try DialogueRuntime(
            store: session.worldState,
            dialogue: dialogueStore(),
            quests: PapyrusQuestFixture.store(PapyrusQuestFixture.quest()),
            fragments: session.bridge
        )

        let choice = try runtime.choose(
            FormID(Self.infoObjectID), speaker: .player
        )
        #expect(choice.dispatchedFragments == ["Fragment_0", "Fragment_1"])
        #expect(choice.unrunFragmentCount == 0)

        PapyrusWorldFixture.drain(session.world)
        let quests = try QuestRuntime(
            store: session.worldState,
            quests: PapyrusQuestFixture.store(PapyrusQuestFixture.quest())
        )
        #expect(try quests.state(of: PapyrusQuestFixture.questFormID)
            .isStageDone(PapyrusQuestFixture.fragmentStage))
    }

    /// A store whose single topic holds the response under test, keyed under
    /// the plugin name the Papyrus fixtures use so the INFO's `ReferenceKey`
    /// matches the instance key.
    private func dialogueStore() throws -> DialogueStore {
        try DialogueStore(
            file: ESMFile(data: DialogueFixture.plugin(
                dialogueChildren: DialogueFixture.topicRecord(
                    formID: 0x0000_1000,
                    fields: DialogueFixture.topicData(category: 0)
                )
                    + DialogueFixture.topicChildren(
                        parent: 0x0000_1000,
                        infos: DialogueFixture.infoRecord(
                            formID: Self.infoObjectID,
                            fields: DialogueFixture.infoData()
                                + Self.infoVMAD()
                        )
                    )
            )),
            pluginName: PapyrusWorldFixture.pluginName
        )
    }
}
