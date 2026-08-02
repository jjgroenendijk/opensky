// Synthetic quest-with-scripts fixture for issue #322: a QUST record carrying
// VMAD scripts and a stage-fragment tail, the store and runtime around it, and
// a world session with the quest layer wired.
//
// Every byte is built in code from the UESP/xEdit layout through `QuestFixture`
// and `VMADFixture`; nothing is extracted from a game install (AGENTS.md
// "Legal & IP boundary").
//
// The `Quest` script object is synthetic too, and deliberately shaped like the
// shipped `Quest.psc`: a parent class whose members are declared `native`. That
// is what makes `someQuest.SetStage(10)` dispatch as the native `Quest.SetStage`
// rather than under the calling script's own name, which is exactly how a real
// install resolves it once `PapyrusWorldRuntime.resolveScript` has pulled the
// parent chain in.

import Foundation
@testable import opensky
import Testing

enum PapyrusQuestFixture {
    static let questObjectID: UInt32 = 0x0000_0700
    static let questEditorID = "OpenSkyProbeQuest"
    static let questScript = "OpenSkyProbeQuestScript"
    static let fragmentScript = "QF_OpenSkyProbeQuest_00000700"
    /// Stage the fragment hangs off, and the one the gate loop sets.
    static let fragmentStage: UInt16 = 10
    /// A stage flagged `startUpStage`, so setting it starts a dormant quest.
    static let startUpStage: UInt16 = 5
    /// A stage flagged `shutDownStage`.
    static let shutDownStage: UInt16 = 90
    static let objectiveIndex: UInt16 = 10

    static var questFormID: FormID {
        FormID(questObjectID)
    }

    static var questKey: ReferenceKey {
        .plugin(name: PapyrusWorldFixture.pluginName, objectID: questObjectID)
    }

    static func instanceKey(_ scriptName: String) -> PapyrusInstanceKey {
        PapyrusInstanceKey(reference: questKey, scriptName: scriptName)
    }

    // MARK: - Record

    /// The QUST record under test: two ordinary stages, a start-up stage, a
    /// shut-down stage, one objective, one attached quest script and a
    /// fragment table whose single entry runs `Fragment_0` for stage 10.
    static func quest(
        startGameEnabled: Bool = true,
        scripts: [VMADFixture.Script]? = nil,
        fragments: [QuestFixture.Fragment]? = nil
    ) throws -> Quest {
        let tail = QuestFixture.fragmentTail(
            fileName: fragmentScript,
            fragments: fragments ?? [
                QuestFixture.Fragment(
                    stage: fragmentStage, script: fragmentScript, function: "Fragment_0"
                )
            ]
        )
        // Assembled step by step rather than as one expression: a single
        // fifteen-term `+` chain over `Data` is what makes the type checker
        // give up (`unable to type-check this expression in reasonable time`).
        var fields = QuestFixture.editorID(questEditorID)
        fields += QuestFixture.general(flags: startGameEnabled ? 1 : 0)
        fields += QuestFixture.vmad(
            scripts: scripts ?? [VMADFixture.Script(questScript, properties: [])],
            tail: tail
        )
        fields += QuestFixture.stage(startUpStage, flags: UInt8(1 << 1))
        fields += QuestFixture.logEntry(text: "Started.")
        fields += QuestFixture.stage(fragmentStage)
        fields += QuestFixture.logEntry(text: "Advanced.")
        fields += QuestFixture.stage(20)
        fields += QuestFixture.logEntry(text: "Later.")
        fields += QuestFixture.stage(shutDownStage, flags: UInt8(1 << 2))
        fields += QuestFixture.logEntry(text: "Done.")
        fields += QuestFixture.objective(objectiveIndex, text: "Do the thing")
        return try QuestFixture.quest(formID: questObjectID, fields: fields)
    }

    /// A store over one quest, keyed by the same resolver every other Papyrus
    /// fixture uses so quest keys and reference keys agree.
    static func store(_ quest: Quest) -> QuestStore {
        QuestStore(quests: [quest], resolver: PapyrusWorldFixture.resolver)
    }

    // MARK: - Scripts

    /// `Quest.psc` as far as these tests need it: every member declared
    /// `native`, so the interpreter resolves the call and names the family.
    static func questClassObject() -> PexObject {
        let natives = [
            ("SetStage", "Bool"), ("SetCurrentStageID", "Bool"),
            ("GetStage", "Int"), ("GetCurrentStageID", "Int"),
            ("GetStageDone", "Bool"), ("IsStageDone", "Bool"),
            ("Start", "Bool"), ("Stop", "None"), ("IsRunning", "Bool"),
            ("IsCompleted", "Bool"), ("CompleteQuest", "None"),
            ("SetObjectiveDisplayed", "None"), ("SetObjectiveCompleted", "None"),
            ("SetObjectiveFailed", "None")
        ]
        return PexFixture.runtimeObject(
            name: "Quest",
            states: [PapyrusTestSupport.state(functions: natives.map { name, returnType in
                (name, PexFixture.runtimeFunction(
                    returnType: returnType, flags: .native, instructions: []
                ))
            })]
        )
    }

    /// The quest's own script: records its `OnInit`, and advances the quest to
    /// the fragment stage when something sends it `OnProbeAdvance`.
    static func questScriptObject() -> PexObject {
        PexFixture.runtimeObject(
            name: questScript,
            parent: "Quest",
            states: [PapyrusTestSupport.state(functions: [
                ("OnInit", PapyrusWorldFixture.probeBody(note: "quest.oninit")),
                ("OnProbeAdvance", setStageBody(fragmentStage))
            ])]
        )
    }

    /// The generated fragment script, which records the stage it ran for.
    static func fragmentScriptObject(
        functions: [(String, PexFunction)]? = nil
    ) -> PexObject {
        PexFixture.runtimeObject(
            name: fragmentScript,
            parent: "Quest",
            states: [PapyrusTestSupport.state(functions: functions ?? [
                ("Fragment_0", PapyrusWorldFixture.probeBody(note: "fragment.10")),
                ("OnInit", PapyrusWorldFixture.probeBody(note: "fragment.oninit"))
            ])]
        )
    }

    /// Every script object a quest session needs, plus whatever the caller adds.
    ///
    /// - Parameter fragmentFunctions: replaces the fragment script's functions,
    ///   for a test that runs a different fragment set.
    static func objects(
        _ extra: [PexObject] = [],
        fragmentFunctions: [(String, PexFunction)]? = nil
    ) -> [PexObject] {
        [
            questClassObject(),
            questScriptObject(),
            fragmentScriptObject(functions: fragmentFunctions)
        ] + extra
    }

    /// `self.SetStage(stage)`, the call a quest script makes to advance itself.
    static func setStageBody(_ stage: UInt16) -> PexFunction {
        PexFixture.runtimeFunction(instructions: [
            PapyrusTestSupport.instruction(
                .callMethod,
                .identifier("SetStage"),
                .identifier("self"),
                .identifier("::nonevar"),
                .integer(1),
                .integer(Int32(stage))
            )
        ])
    }

    // MARK: - Session

    /// A world session with the quest layer wired and, unless told otherwise,
    /// the running quests' scripts already instantiated.
    ///
    /// `OnInit` is left queued: call `PapyrusWorldFixture.drain(_:)` to run it.
    @MainActor
    static func session(
        quest: Quest,
        objects questObjects: [PexObject]? = nil,
        entries: [RuntimeReferenceEntry] = [],
        worldState: WorldStateStore = WorldStateStore(),
        attachQuests: Bool = true
    ) -> PapyrusWorldFixture.Session {
        let session = PapyrusWorldFixture.session(
            objects: questObjects ?? objects(),
            entries: entries,
            worldState: worldState,
            attach: !entries.isEmpty
        )
        session.bridge.questRuntime = QuestRuntime(
            store: session.worldState, quests: store(quest)
        )
        if attachQuests {
            session.bridge.attachRunningQuestScripts()
        }
        return session
    }

    /// The quest's effective state in a session, or a recorded failure.
    @MainActor
    static func state(
        _ session: PapyrusWorldFixture.Session
    ) throws -> QuestRuntimeState {
        try #require(session.bridge.questRuntime).state(of: questFormID)
    }
}
