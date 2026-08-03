// The records and compiled scripts behind `M13AcceptanceChain` (issue #185).
//
// Split from the chain because the chain is the wiring and this is the data:
// one QUST assembled field by field from the published layout, two REFR
// records, and the five PEX objects a quest session needs. Every byte is built
// in code (AGENTS.md "Legal & IP boundary").
//
// The scripts are shaped the way a real install's are, which is what makes the
// dispatch real rather than arranged:
//
// * `Quest` is a parent class whose members are all `native`, exactly as the
//   shipped `Quest.psc` declares them, so `theQuest.SetStage(10)` resolves as
//   the native `Quest.SetStage` rather than under the calling script's name.
// * `QF_OpenSkyGateQuest_00000900` is the generated fragment script the VMAD
//   tail names, extending `Quest` so its own `Self` is the quest.
// * `OpenSkyGateLeverScript` reaches its quest through an automatic VMAD
//   property, which is how an authored lever names the quest it advances.

import Foundation
@testable import opensky

/// Main-actor isolated only because it reads `M13AcceptanceChain`'s constants,
/// which belong beside the chain that names them. Nothing here needs the actor
/// otherwise: every call assembles bytes or values.
@MainActor
enum M13AcceptanceFixture {
    private typealias Chain = M13AcceptanceChain

    // MARK: - The QUST record

    /// The gate's quest: a main-quest-typed, journal-visible record with two
    /// stages carrying journal text, one objective, one attached quest script,
    /// a fragment table whose single entry runs `Fragment_0` for stage 10, and
    /// one forced-reference alias carrying a `ReferenceAlias` script.
    ///
    /// Deliberately *not* start-game-enabled: the gate starts it, so the start
    /// is a step of the loop rather than a property of the fixture.
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

    /// The generated fragment script:
    ///
    /// ```papyrus
    /// Function Fragment_0()
    ///     Probe.Note("fragment.10")
    ///     SetObjectiveDisplayed(10)
    /// EndFunction
    /// ```
    ///
    /// The `SetObjectiveDisplayed` call is what makes the fragment mutate world
    /// state rather than only prove it ran, and it is the shape a Creation Kit
    /// stage fragment really has — the generated script extends `Quest`, so an
    /// unqualified objective call dispatches on the quest itself.
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

    /// The lever:
    ///
    /// ```papyrus
    /// Quest Property GateQuest Auto
    ///
    /// Event OnActivate(ObjectReference akActionRef)
    ///     Probe.Seen(akActionRef)
    ///     GateQuest.SetStage(10)
    /// EndEvent
    /// ```
    ///
    /// assembled as the instructions a compiler emits for it. The `Probe.Seen`
    /// call is the gate's only addition and observes `akActionRef` without
    /// touching the world.
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
