// Real-data acceptance: the scripts of `MGRArniel01`, the cheapest quest on the
// census shortlist (docs/formats/quest-records.md), bind and run their first
// stage fragment, with the tallies pinned. The report goes to gitignored `.logs/`
// and holds counts and editor IDs only.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyQuests
@testable import OpenSkyQuestsInterface
@testable import OpenSkyScripting
@testable import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

struct QuestScriptRealDataTests {
    private static let targetEditorID = "MGRArniel01"

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot)) @MainActor
    func runsTheTargetQuestsFirstStageFragment() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
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
                context: PapyrusNativeContext(world: bridge)
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

        // The one attach skip is an `OnInit` the fragment script does not declare.
        // No cell is loaded, but each object property still binds: a reference in an
        // unloaded cell gets a handle when a script first uses it. The one filled alias
        // binds to its reference's handle.
        #expect(world.skips.total == 1)
        #expect(world.skips.counts[.undefinedEventFunction] == 1)
        #expect(world.bindingSkips.counts[.unresolvedReference] == nil)
        #expect(world.bindingSkips.counts[.aliasObject] == nil)
        #expect(world.aliasResolution.filledAliasCount == 1)

        let report = Self.report(
            quest: quest,
            stage: firstFragmentStage,
            world: world,
            state: state
        )
        print(report)
        let logs = try RepositoryLogs.directory()
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
