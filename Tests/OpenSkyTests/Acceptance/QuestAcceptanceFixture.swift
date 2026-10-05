// Records and compiled scripts behind `QuestAcceptanceChain`: one QUST, two REFR,
// and five PEX objects. `Quest` has only `native` members, as in `Quest.psc`;
// the fragment script extends `Quest`; the lever finds its quest through an
// automatic VMAD property.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsPEX
import OpenSkyScriptingFixtures
@testable import OpenSkyWorldState

/// Main-actor isolated only because it reads `QuestAcceptanceChain`'s constants,
/// which belong beside the chain that names them. Nothing here needs the actor
/// otherwise: every call assembles bytes or values.
@MainActor
enum QuestAcceptanceFixture {
    private typealias Chain = QuestAcceptanceChain

    // MARK: - The QUST record

    /// The gate's quest: main-quest type, journal-visible, two stages with
    /// text, one objective, a script, a stage-10 fragment, and a forced alias.
    /// Not start-game-enabled, because starting it is a step of the loop.
    static func quest() throws -> Quest {
        let tail = QuestFixture.fragmentTail(
            fileName: Chain.fragmentScript,
            fragments: [QuestFixture.Fragment(
                stage: Chain.leverStage,
                script: Chain.fragmentScript,
                function: "Fragment_0"
            )],
            aliases: [QuestFixture.AliasScripts(
                object: ScriptObjectReference(
                    formID: Chain.questFormID, alias: Int16(Chain.aliasID), unused: 0
                ),
                scripts: [VMADFixture.Script(Chain.aliasScript, properties: [])]
            )]
        )
        // Assembled step by step rather than as one expression: a long `+`
        // chain over `Data` is what makes the type checker give up.
        var fields = QuestFixture.editorID(Chain.questEditorID)
        fields += QuestFixture.general(type: 1)
        fields += QuestFixture.full(Chain.questTitle)
        fields += QuestFixture.vmad(
            scripts: [VMADFixture.Script(Chain.questScript, properties: [])], tail: tail
        )
        fields += QuestFixture.stage(Chain.leverStage)
        fields += QuestFixture.logEntry(text: Chain.firstJournalText)
        fields += QuestFixture.stage(Chain.finalStage)
        fields += QuestFixture.logEntry(text: Chain.secondJournalText)
        fields += QuestFixture.objective(Chain.objectiveIndex, text: Chain.objectiveText)
        fields += QuestFixture.marker("ANAM")
        fields += QuestFixture.alias(
            id: Chain.aliasID,
            name: "GateTarget",
            fill: QuestFixture.word("ALFR", Chain.aliasTargetObjectID)
        )
        return try QuestFixture.quest(formID: Chain.questObjectID, fields: fields)
    }

    // MARK: - The placed references

    /// The lever the player activates and the reference the alias is forced
    /// onto. The lever carries the quest property; the alias target carries no
    /// script of its own, so the only instance it ever holds is the one the
    /// quest's alias section puts there.
    static func entries() throws -> [RuntimeReferenceEntry] {
        try [
            PapyrusWorldFixture.referenceEntry(
                objectID: Chain.leverObjectID,
                scripts: [VMADFixture.Script(Chain.leverScript, properties: [
                    VMADFixture.Property(
                        "GateQuest", .object(VMADFixture.object(Chain.questObjectID))
                    )
                ])],
                isPersistent: true
            ),
            PapyrusWorldFixture.referenceEntry(objectID: Chain.aliasTargetObjectID, scripts: [])
        ]
    }

    // MARK: - The compiled scripts

    static func objects() -> [PexObject] {
        [
            PapyrusQuestFixture.questClassObject(),
            questScriptObject(),
            fragmentScriptObject(),
            aliasScriptObject(),
            leverScriptObject()
        ]
    }

    /// The quest's own script. It records its `OnInit` and does nothing else:
    /// the gate's advance comes from the world, not from the quest talking to
    /// itself.
    private static func questScriptObject() -> PexObject {
        PexFixture.runtimeObject(
            name: Chain.questScript,
            parent: "Quest",
            states: [PapyrusTestSupport.state(functions: [
                ("OnInit", PapyrusWorldFixture.probeBody(note: "quest.oninit"))
            ])]
        )
    }

    /// The generated fragment script: `Fragment_0()` calls
    /// `Probe.Note("fragment.10")` and `SetObjectiveDisplayed(10)`. It extends
    /// `Quest`, so the unqualified call dispatches on the quest, as in a real
    /// stage fragment.
    private static func fragmentScriptObject() -> PexObject {
        let body = PexFixture.runtimeFunction(instructions: [
            PapyrusTestSupport.instruction(
                .callStatic,
                .identifier("Probe"),
                .identifier("Note"),
                .identifier("::nonevar"),
                .integer(1),
                .string("fragment.10")
            ),
            PapyrusTestSupport.instruction(
                .callMethod,
                .identifier("SetObjectiveDisplayed"),
                .identifier("self"),
                .identifier("::nonevar"),
                .integer(1),
                .integer(Int32(Chain.objectiveIndex))
            )
        ])
        return PexFixture.runtimeObject(
            name: Chain.fragmentScript,
            parent: "Quest",
            states: [PapyrusTestSupport.state(functions: [("Fragment_0", body)])]
        )
    }

    /// The `ReferenceAlias` script the quest's alias carries, which records its
    /// `OnInit` the way every other probe script does. It runs on the filled
    /// reference rather than on the quest, which is what the note proves.
    private static func aliasScriptObject() -> PexObject {
        PexFixture.runtimeObject(
            name: Chain.aliasScript,
            states: [PapyrusTestSupport.state(functions: [
                ("OnInit", PapyrusWorldFixture.probeBody(note: "alias.oninit"))
            ])]
        )
    }

    /// The lever: `Quest Property GateQuest Auto`, and `OnActivate` calls
    /// `Probe.Seen(akActionRef)` then `GateQuest.SetStage(10)`, assembled as a
    /// compiler would emit it. `Probe.Seen` only observes.
    private static func leverScriptObject() -> PexObject {
        let body = PexFixture.runtimeFunction(
            parameters: [PexTypedName(name: "akActionRef", typeName: "ObjectReference")],
            instructions: [
                PapyrusTestSupport.instruction(
                    .callStatic,
                    .identifier("Probe"),
                    .identifier("Seen"),
                    .identifier("::nonevar"),
                    .integer(1),
                    .identifier("akActionRef")
                ),
                PapyrusTestSupport.instruction(
                    .callMethod,
                    .identifier("SetStage"),
                    .identifier("::GateQuest_var"),
                    .identifier("::nonevar"),
                    .integer(1),
                    .integer(Int32(Chain.leverStage))
                )
            ]
        )
        return PexFixture.runtimeObject(
            name: Chain.leverScript,
            variables: [PexVariable(
                name: "::GateQuest_var",
                typeName: "Quest",
                userFlags: 0,
                initialValue: .null
            )],
            properties: [PexProperty(
                name: "GateQuest",
                typeName: "Quest",
                documentation: "",
                userFlags: 0,
                flags: [.readable, .writable, .automatic],
                automaticVariableName: "::GateQuest_var",
                readHandler: nil,
                writeHandler: nil
            )],
            states: [PapyrusTestSupport.state(functions: [("OnActivate", body)])]
        )
    }
}
