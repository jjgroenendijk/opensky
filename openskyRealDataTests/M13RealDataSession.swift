// The session and the report behind `M13AcceptanceRealDataTests` (issue #185).
//
// Split from the test for the reason every other real-data suite splits: the
// wiring is a paragraph of plumbing that says nothing about the gate, and the
// report is a formatter. Both are shared with the save half, which builds a
// second session over the same install.
//
// Nothing is written into the install. The quest state lives in an in-memory
// `WorldStateStore`, and the save slot the gate writes goes to a temporary
// directory the test removes.

import Foundation
@testable import opensky

/// One headless engine over the user's install: the plugin's quests, the
/// Papyrus world runtime with the install's own scripts behind it, and the
/// quest layer joining them.
@MainActor
final class M13RealDataSession {
    /// The four quest condition functions issue #182 registered, by raw
    /// on-disk index: `GetQuestRunning`, `GetStage`, `GetStageDone` and
    /// `GetQuestCompleted`. The Creation Kit spells each 4096 higher.
    static let questConditionIndices: [UInt16] = [56, 58, 59, 543]

    let root: GameDataRoot
    let quests: QuestStore
    let worldState = WorldStateStore()
    let bridge: PapyrusWorldStateBridge
    let world: PapyrusWorldRuntime
    private let fileSystem: VirtualFileSystem

    init(root: GameDataRoot, pluginName: String) throws {
        self.root = root
        let file = try ESMFile(url: root.dataURL.appending(path: pluginName))
        quests = QuestStore(file: file, pluginName: pluginName)
        fileSystem = VirtualFileSystem(root: root)
        bridge = PapyrusWorldStateBridge(worldState: worldState)
        world = PapyrusWorldRuntime(runtime: PapyrusRuntime(
            files: [],
            nativeDispatch: PapyrusNativeRegistry.standard(
                context: PapyrusNativeContext(world: PapyrusWorldAccess(bridge: bridge))
            )
        ))
        bridge.world = world
        bridge.questRuntime = QuestRuntime(store: worldState, quests: quests)
        let loader = PexScriptLoader(fileSystem: fileSystem)
        world.scriptProvider = { try? loader.load($0) }
    }

    var runtime: QuestRuntime {
        get throws {
            guard let questRuntime = bridge.questRuntime else {
                throw M13RealDataError.noQuestRuntime
            }
            return questRuntime
        }
    }

    func state(of id: FormID) throws -> QuestRuntimeState {
        try runtime.state(of: id)
    }

    /// Starts the quest, walks every stage it declares in order, shows and
    /// completes every objective, and flags the quest complete — draining the
    /// script queue after each stage so its fragments run before the next one.
    ///
    /// The stages are set from outside because this quest advances through
    /// dialogue, which OpenSky does not have yet; see the suite's header.
    func walk(quest: Quest, key: ReferenceKey) throws {
        guard try bridge.startQuest(for: key) else {
            throw M13RealDataError.questWouldNotStart
        }
        drain()
        for stage in Set(quest.stages.map(\.index)).sorted() {
            _ = try bridge.setQuestStage(stage, for: key)
            drain()
        }
        for objective in quest.objectives.map(\.index) {
            try bridge.setQuestObjectiveDisplayed(objective, true, for: key)
            try bridge.setQuestObjectiveCompleted(objective, true, for: key)
        }
        try bridge.completeQuest(for: key)
        drain()
    }

    /// The journal page as the player would see it, resolved through the
    /// plugin's own string tables and the quest's filled aliases — the same
    /// call `GameViewController` makes.
    func journal() throws -> JournalMenuModel {
        try JournalMenuModel.build(
            runtime: runtime,
            strings: LocalizedStrings(vfs: fileSystem, pluginName: "Skyrim.esm"),
            aliases: .none
        )
    }

    /// Every condition the quest record declares, across all five places a
    /// QUST can carry them. The census says the target quest declares none;
    /// this is what makes that a checked claim rather than a remembered one.
    static func conditionCount(of quest: Quest) -> Int {
        var total = quest.dialogueConditions.conditions.count
        total += quest.storyManagerConditions.conditions.count
        total += quest.stages.reduce(0) { sum, stage in
            sum + stage.logEntries.reduce(0) { $0 + $1.conditions.conditions.count }
        }
        total += quest.objectives.reduce(0) { sum, objective in
            sum + objective.targets.reduce(0) { $0 + $1.conditions.conditions.count }
        }
        total += quest.aliases.reduce(0) { $0 + $1.matchConditions.conditions.count }
        return total
    }

    /// Starts the quest and walks it to `stage`, draining the script queue so
    /// that stage's fragments have run before the caller looks at anything.
    /// The render half uses this to build two pages one stage apart.
    func start(quest: Quest, key: ReferenceKey, upTo stage: UInt16) throws {
        guard try bridge.startQuest(for: key) else {
            throw M13RealDataError.questWouldNotStart
        }
        drain()
        for index in Set(quest.stages.map(\.index)).sorted() where index <= stage {
            _ = try bridge.setQuestStage(index, for: key)
            drain()
        }
        for objective in quest.objectives.map(\.index) {
            try bridge.setQuestObjectiveDisplayed(objective, true, for: key)
        }
    }

    /// Records one more stage as reached, which is what puts a new paragraph
    /// on the journal page.
    func advance(to stage: UInt16, key: ReferenceKey) throws {
        _ = try bridge.setQuestStage(stage, for: key)
        drain()
    }

    /// Steps until a tick neither dispatches nor leaves anything queued,
    /// bounded so a broken queue fails the test rather than hanging.
    func drain(maxSteps: Int = 64) {
        for _ in 0 ..< maxSteps {
            let report = world.stepFixed()
            if report.dispatched == 0, report.resumed == 0, report.queued == 0 {
                return
            }
        }
    }
}

nonisolated enum M13RealDataError: Error {
    case noQuestRuntime
    case questWouldNotStart
}

/// The gate's numeric evidence, written to gitignored `logs/`.
///
/// Counts, editor IDs and tally names only. No journal text, no objective text
/// and no script body ever reaches the file: those are the plugin's own strings
/// (AGENTS.md "Legal & IP boundary").
@MainActor
enum M13RealDataReport {
    static func write(
        session: M13RealDataSession,
        quest: Quest,
        state: QuestRuntimeState,
        conditions: ConditionTally
    ) throws {
        let report = text(
            session: session, quest: quest, state: state, conditions: conditions
        )
        print(report)
        let logs = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
        try FileManager.default.createDirectory(
            at: logs, withIntermediateDirectories: true
        )
        try report.write(
            to: logs.appending(path: "m13-acceptance.log"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func text(
        session: M13RealDataSession,
        quest: Quest,
        state: QuestRuntimeState,
        conditions: ConditionTally
    ) -> String {
        let world = session.world
        let page = (try? session.journal().entries.first { $0.formID == quest.formID })
        var lines = [
            "OpenSky M13 acceptance (issue #185)",
            "quest: \(quest.editorID ?? "unnamed") type \(quest.kind.name) "
                + "stages \(quest.stages.count) objectives \(quest.objectives.count) "
                + "aliases \(quest.aliases.count) fragments \(quest.fragments.count)",
            "declared conditions: \(M13RealDataSession.conditionCount(of: quest))",
            "reached stages: \(state.stagesReached.count) "
                + "current \(state.stageValue) completed \(state.isCompleted)",
            "objectives displayed: \(state.objectives.count { $0.isDisplayed }) "
                + "completed \(state.objectives.count { $0.isCompleted })",
            "quest script instances: \(world.questInstanceKeys.count) "
                + "alias instances: \(world.questAliasInstanceCount)",
            "fragments queued: \(world.questFragmentsQueued) "
                + "last: \(world.lastQuestFragment ?? "none")",
            "aliases filled: \(world.aliasResolution.filledAliasCount)",
            "native calls: \(world.runtime.tally.nativeCallTotal) "
                + "unimplemented: \(world.runtime.tally.unimplementedNativeTotal)",
            "faults: \(world.runtime.tally.faultTotal) skips: \(world.skips.total) "
                + "binding skips: \(world.bindingSkips.total)",
            "condition evaluations: \(conditions.conditionsEvaluated) "
                + "unresolved quests: \(conditions.unresolvedQuestTotal) "
                + "unknown functions: \(conditions.unknownFunctionTotal)",
            "journal rows on the page: \(page.map { _ in 1 } ?? 0) "
                + "objective rows: \(page?.objectives.count ?? 0) "
                + "journal paragraphs: \(page?.logEntries.count ?? 0)"
        ]
        for (kind, count) in world.runtime.tally.faultKindCounts.sorted(by: { $0.key < $1.key }) {
            lines.append("fault \(kind) \(count)")
        }
        // Type names and instruction offsets only: a fault case carries no
        // script text, so this stays inside the counts-and-ids rule.
        for fault in world.runtime.tally.faults.prefix(5) {
            lines.append("fault detail \(fault)")
        }
        for entry in world.runtime.tally.rankedUnimplementedNatives.prefix(10) {
            lines.append("unimplemented \(entry.name) \(entry.count)")
        }
        for entry in world.skips.ranked {
            lines.append("skip \(entry.name) \(entry.count)")
        }
        for entry in world.bindingSkips.ranked {
            lines.append("binding skip \(entry.name) \(entry.count)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
