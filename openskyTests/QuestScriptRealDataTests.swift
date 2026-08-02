// Env-gated acceptance for issue #322 over the user's own install: the
// census-chosen target quest's scripts instantiate against real data, its
// first stage fragment runs, and the unimplemented and fault tallies are
// pinned rather than described.
//
// The quest is `MGRArniel01`, the cheapest entry on the 13.1 census shortlist
// (docs/formats/records.md): two stages, one objective, one forced-reference
// alias, two fragments and no conditions. Named here rather than rediscovered,
// because the shortlist is the record of that choice.
//
// Nothing from the install is committed: the report goes to gitignored `logs/`
// and carries counts and editor IDs only. Run it with
// `make realtest T='QuestScriptRealDataTests/runsTheTargetQuestsFirstStageFragment()'`,
// which supplies the data root and the RSS watchdog.

import Foundation
@testable import opensky
import Testing

struct QuestScriptRealDataTests {
    private static let targetEditorID = "MGRArniel01"

    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil)) @MainActor
    func runsTheTargetQuestsFirstStageFragment() throws {
        let root = try #require(Self.dataRoot)
        let pluginName = "Skyrim.esm"
        let file = try ESMFile(url: root.dataURL.appending(path: pluginName))
        let quests = QuestStore(file: file, pluginName: pluginName)
        let quest = try #require(quests.quest(editorID: Self.targetEditorID))
        let key = try #require(quests.key(for: quest.formID))

        let worldState = WorldStateStore()
        let bridge = PapyrusWorldStateBridge(worldState: worldState)
        let world = PapyrusWorldRuntime(runtime: PapyrusRuntime(
            files: [],
            nativeDispatch: PapyrusNativeRegistry.standard(
                context: PapyrusNativeContext(world: PapyrusWorldAccess(bridge: bridge))
            )
        ))
        bridge.world = world
        bridge.questRuntime = QuestRuntime(store: worldState, quests: quests)
        let loader = PexScriptLoader(fileSystem: VirtualFileSystem(root: root))
        world.scriptProvider = { try? loader.load($0) }

        // Start, then advance to the lowest stage the fragment table covers:
        // the quest is not start-game-enabled, and only a running quest takes
        // an ordinary stage.
        #expect(try bridge.startQuest(for: key))
        let firstFragmentStage = try #require(quest.fragments.map(\.stageIndex).min())
        #expect(try bridge.setQuestStage(firstFragmentStage, for: key))
        for _ in 0 ..< 32 where world.eventQueue.isEmpty == false {
            world.stepFixed()
        }

        let state = try #require(bridge.questRuntime).state(of: quest.formID)
        #expect(state.isRunning)
        #expect(state.isStageDone(firstFragmentStage))
        #expect(world.questCount == 1)
        // One script: this quest's whole VMAD is the generated fragment
        // script, which the fragment tail names as well, and the two spellings
        // collapse onto one instance.
        #expect(world.questInstanceKeys.count == 1)
        #expect(world.questFragmentsQueued == 1)
        #expect(world.lastQuestFragment == "Fragment_2 -> qf_mgrarniel01_0006a086")
        #expect(world.runtime.tally.faultTotal == 0)
        #expect(world.runtime.tally.nativeCallTotal == 1)
        #expect(world.runtime.tally.unimplementedNativeTotal == 0)
        #expect(world.eventQueue.isEmpty)

        // The one attach skip is the `OnInit` a generated fragment script does
        // not declare, which is counted rather than faulted. The binding skips
        // are the alias-typed and reference-typed properties #183 resolves;
        // they leave the compiler defaults in place, which is why the fragment
        // still runs.
        #expect(world.skips.total == 1)
        #expect(world.skips.counts[.undefinedEventFunction] == 1)
        #expect(world.bindingSkips.counts[.unresolvedReference] == 4)
        #expect(world.bindingSkips.counts[.aliasObject] == 1)

        let report = Self.report(
            quest: quest,
            stage: firstFragmentStage,
            world: world,
            state: state
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
            to: logs.appending(path: "quest-scripts-probe.log"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// Counts and editor IDs only — never journal text, never a script body.
    @MainActor
    private static func report(
        quest: Quest,
        stage: UInt16,
        world: PapyrusWorldRuntime,
        state: QuestRuntimeState
    ) -> String {
        var lines = [
            "OpenSky quest script probe (issue #322)",
            "quest: \(quest.editorID ?? "unnamed") stages \(quest.stages.count) "
                + "objectives \(quest.objectives.count) fragments \(quest.fragments.count)",
            "scripts: \(quest.script.scripts.map(\.name).sorted().joined(separator: ", "))",
            "fragment script: \(quest.script.questFragments?.fileName ?? "none")",
            "instances: \(world.questInstanceKeys.count) "
                + "stage set: \(stage) reached: \(state.stagesReached)",
            "fragments queued: \(world.questFragmentsQueued) "
                + "last: \(world.lastQuestFragment ?? "none")",
            "native calls: \(world.runtime.tally.nativeCallTotal) "
                + "unimplemented: \(world.runtime.tally.unimplementedNativeTotal)",
            "faults: \(world.runtime.tally.faultTotal) skips: \(world.skips.total)"
        ]
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
