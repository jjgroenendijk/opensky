// The M13 gate's world, built once and driven step by step (issue #185).
//
// One synthetic journal-visible quest, one lever that activates it, and one
// reference its single alias is forced onto. The lever's compiled `OnActivate`
// body calls `SetStage` on a VMAD quest property, so the whole path from a
// raycast use-key press to a mutated `WorldStateStore` is the shipping one:
//
//   CellStreamer raycast -> InteractionEvent -> PapyrusWorldStateBridge
//   -> OnActivate -> Quest.SetStage native -> QuestRuntime -> stage fragment
//   -> Quest.SetObjectiveDisplayed native -> QuestRuntime
//
// Nothing here is a shortcut around a layer: every arrow is the same call the
// app makes. The one place this fixture enters below the app is the use-key
// press, which is `CellStreamer.update(cameraPosition:interactionRay:activate:)`
// — the call the render loop makes every frame — because everything above it is
// `GameViewController` key handling and an `MTKView` draw callback, neither of
// which a headless test can honestly drive. That is the same entry point
// `M11ScriptedWorldChain` uses.
//
// Every byte is assembled in code from the published QUST, REFR and PEX layouts
// (AGENTS.md "Legal & IP boundary"); nothing is extracted from an install, and
// nothing here needs a Metal device or game data.

import Foundation
@testable import opensky
import simd
import Testing

/// The gate's world. `init` only wires it; the loop steps are separate calls so
/// a failure names the step rather than leaving an end state to explain.
@MainActor
struct M13AcceptanceChain {
    // MARK: - Identities

    static let questObjectID: UInt32 = 0x0000_0900
    static let leverObjectID: UInt32 = 0x0000_0901
    /// The reference the quest's one alias is forced onto, and the one the
    /// `ReferenceAlias` script rides on once the quest starts.
    static let aliasTargetObjectID: UInt32 = 0x0000_0902

    static let questEditorID = "OpenSkyGateQuest"
    static let questTitle = "The Gate"
    static let questScript = "OpenSkyGateQuestScript"
    static let fragmentScript = "QF_OpenSkyGateQuest_00000900"
    static let leverScript = "OpenSkyGateLeverScript"
    static let aliasScript = "OpenSkyGateAliasScript"

    /// The stage the lever sets, the one carrying the fragment, and the one
    /// whose journal paragraph the page has to grow.
    static let leverStage: UInt16 = 10
    /// A plain later stage, set by hand at the end of the loop.
    static let finalStage: UInt16 = 20
    static let objectiveIndex: UInt16 = 10
    static let aliasID: UInt32 = 0

    static let firstJournalText = "The lever in the hall has been pulled."
    static let secondJournalText = "The gate stands open."
    static let objectiveText = "Pull the lever"

    /// The cell both the lever and the alias target live in.
    static let cell = CellSceneLocation.exterior(CellCoordinate(x: 0, y: 0))

    static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: PapyrusWorldFixture.pluginName, objectID: objectID)
    }

    static var questKey: ReferenceKey {
        key(questObjectID)
    }

    static var questFormID: FormID {
        FormID(questObjectID)
    }

    static func instanceKey(_ scriptName: String) -> PapyrusInstanceKey {
        PapyrusInstanceKey(reference: questKey, scriptName: scriptName)
    }

    // MARK: - Wiring

    let quest: Quest
    let session: PapyrusWorldFixture.Session
    let streamer: CellStreamer
    private let runner = ManualCellBuildRunner()
    private let entries: [RuntimeReferenceEntry]

    /// What script code saw, so `akActionRef` is asserted on the value the
    /// bytecode passed rather than on the queued event.
    let recorder = M11ScriptedWorldRecorder()

    init() throws {
        quest = try M13AcceptanceFixture.quest()
        entries = try M13AcceptanceFixture.entries()
        // The cell attach is deferred: the lever's quest property can only
        // resolve to a live handle once the quest's own instances exist, which
        // is also the order a session brings them up — quests at wire-up,
        // cells as they stream in.
        session = PapyrusWorldFixture.session(
            objects: M13AcceptanceFixture.objects(),
            entries: entries,
            cell: Self.cell,
            attach: false
        )
        session.bridge.questRuntime = QuestRuntime(
            store: session.worldState,
            quests: QuestStore(quests: [quest], resolver: PapyrusWorldFixture.resolver)
        )
        streamer = CellStreamerTests.makeStreamer(runner: runner, radius: 0)
        // From here on the streamer answers every world lookup, so cell
        // attribution is the engine's answer rather than the fixture's.
        session.bridge.references = streamer
        let recorder = recorder
        session.dispatch.probeHandler = { call, _ in
            guard PapyrusRuntime.matches(call.functionName, "Seen") else { return nil }
            recorder.seen.append(contentsOf: call.arguments)
            return .returned(.none)
        }
        streamer.onInteraction.add { [weak bridge = session.bridge] event in
            bridge?.handleInteraction(event)
        }
        integrateCell()
    }

    var runtime: QuestRuntime {
        get throws {
            try #require(session.bridge.questRuntime)
        }
    }

    var state: QuestRuntimeState {
        get throws {
            try runtime.state(of: Self.questFormID)
        }
    }

    /// Notes the probe dispatch recorded, which is the execution trace the gate
    /// asserts its ordering on.
    var notes: [String] {
        session.dispatch.notes
    }

    // MARK: - Loop steps

    /// Step 1 — the quest starts. Its aliases fill, its scripts instantiate and
    /// their `OnInit` fires.
    func startQuest() throws {
        try session.bridge.startQuest(for: Self.questKey)
        PapyrusWorldFixture.drain(session.world)
    }

    /// Step 2 — the cell the lever is in attaches, binding the lever's quest
    /// property to the live quest instance.
    func attachCell() {
        session.world.attach(
            cell: Self.cell,
            references: RuntimeReferenceIndex(entries: entries),
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        PapyrusWorldFixture.drain(session.world)
    }

    /// Step 3 — the player presses the use key while looking at the lever. Two
    /// updates because the first one publishes the target and the second one
    /// activates it, exactly as a held key produces two frames.
    func pressUseKey() {
        let ray = CellStreamerTests.interactionRay(
            from: CellStreamerTests.center, to: Self.leverTarget
        )
        streamer.update(cameraPosition: CellStreamerTests.center, interactionRay: ray)
        streamer.update(
            cameraPosition: CellStreamerTests.center, interactionRay: ray, activate: true
        )
        PapyrusWorldFixture.drain(session.world)
    }

    /// The journal page as the player would see it, built from live quest state
    /// through the same `JournalMenuModel.build` the app's panel calls.
    ///
    /// `strings: nil` because the fixture plugin's header does not say
    /// localized, so its text is written inline and there is no table to
    /// consult — the unlocalized-mod-plugin path, not a test-only one.
    func journal(selecting editorID: String = questEditorID) throws -> JournalMenuModel {
        var model = try JournalMenuModel.build(runtime: runtime, strings: nil)
        let row = try #require(
            model.entries.firstIndex { $0.editorID == editorID },
            "the gate quest is not on the journal page"
        )
        model.select(row)
        return model
    }

    // MARK: - The cell

    /// Completes the one cell build the streamer asks for, with the lever
    /// carrying an `activate` interaction and a collision shape to raycast at.
    private func integrateCell() {
        let lever = PapyrusWorldActivationTests.interaction(
            reference: Self.leverObjectID, action: .activate
        )
        streamer.update(cameraPosition: CellStreamerTests.center)
        runner.complete(
            CellStreamerTests.coordinate(0, 0),
            with: .success(CellStreamerTests.cellScene(
                location: Self.cell,
                interactions: [lever.reference: lever],
                staticCollision: Self.leverCollision,
                references: RuntimeReferenceIndex(entries: entries)
            ))
        )
    }

    /// Where the lever's collision shape sits, a short walk from the camera so
    /// the view ray reaches it.
    private static var leverTarget: SIMD3<Float> {
        CellStreamerTests.center + SIMD3<Float>(10, 0, 0)
    }

    private static var leverCollision: StaticCollisionSet {
        let extent = SIMD3<Float>(repeating: 1)
        let position = leverTarget
        var stats = StaticCollisionStats()
        stats.shapeCount = 1
        return StaticCollisionSet(
            location: nil,
            shapes: [StaticCollisionShape(
                reference: FormID(leverObjectID),
                transform: MatrixMath.translation(position),
                geometry: .box(halfExtents: extent),
                bounds: ModelBounds(min: position - extent, max: position + extent)
            )],
            stats: stats
        )
    }
}

/// The far side of the gate's save/load step: a session over the same quest
/// record with nothing in it, which a saved file is restored into.
///
/// No streamer and no cell: a load resumes quest state and quest scripts, and
/// the point of the step is that it does so without the world that produced
/// them. `attachQuests` is off so the restore drives the attach, exactly as the
/// app's load path does.
@MainActor
struct M13AcceptanceRestore {
    let session: PapyrusWorldFixture.Session

    init(quest: Quest) {
        session = PapyrusWorldFixture.session(
            objects: M13AcceptanceFixture.objects(), entries: [], attach: false
        )
        session.bridge.questRuntime = QuestRuntime(
            store: session.worldState,
            quests: QuestStore(quests: [quest], resolver: PapyrusWorldFixture.resolver)
        )
    }

    var state: QuestRuntimeState {
        get throws {
            try #require(session.bridge.questRuntime)
                .state(of: M13AcceptanceChain.questFormID)
        }
    }

    func journal() throws -> JournalMenuModel {
        let runtime = try #require(session.bridge.questRuntime)
        var model = JournalMenuModel.build(runtime: runtime, strings: nil)
        let row = try #require(
            model.entries.firstIndex { $0.editorID == M13AcceptanceChain.questEditorID },
            "the restored session lost the gate quest"
        )
        model.select(row)
        return model
    }
}
