// `openskycli sweep quests`: starts every quest the game starts on its own, headless, and
// ranks what stops them (docs/tools/headless-sweeps.md, "Quest sweep").

import Foundation
import OpenSkyCLIArguments
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyScripting

@MainActor
enum SweepQuestsCommand {
    static func run(context: CLIContext, arguments: SweepArguments.Quests) throws {
        let engine = try SweepEngine(context: context)
        let story = storyManagerQuests(StoryManagerStore(plugins: engine.plugins.files))
        let starting = engine.quests.sortedQuests().filter { quest in
            quest.flags.contains(.startGameEnabled)
                || engine.quests.key(for: quest.formID).map(story.contains) == true
        }
        let scenes = SceneStore(plugins: engine.plugins.files).scenes.records
            .map(\.record).filter { $0.flags.contains(.beginOnQuestStart) }
        let scenesByQuest = Dictionary(grouping: scenes) { $0.quest?.rawValue ?? 0 }
        var report = HeadlessSweepReport()
        for quest in starting {
            guard let key = engine.quests.key(for: quest.formID) else { continue }
            report.noteRun()
            let name = quest.editorID ?? quest.formID.description
            for problem in start(quest, key: key, engine: engine) {
                report.note(problem, subject: name)
            }
            for scene in scenesByQuest[quest.formID.rawValue] ?? [] {
                for problem in sceneProblems(scene, quest: quest, engine: engine) {
                    report.note(problem, subject: name)
                }
            }
        }
        let text = report.text(unit: "quests", limit: nil, examples: arguments.report.examples)
        let directory = try engine.write(
            report: text,
            name: "sweep-quests",
            out: arguments.report.out
        )
        print(
            report.text(
                unit: "quests",
                limit: arguments.report.limit,
                examples: arguments.report.examples
            ),
            terminator: ""
        )
        print("[INFO] report and fallbacks.tsv: \(directory.path(percentEncoded: false))")
    }

    /// Every quest a story-manager quest node can start.
    private static func storyManagerQuests(_ store: StoryManagerStore) -> Set<ReferenceKey> {
        var keys: Set<ReferenceKey> = []
        for node in store.nodes.records where node.record.kind == .quest {
            for entry in node.record.quests {
                if let id = store.nodes.index.resolvedID(
                    entry.quest,
                    fromPlugin: node.sourcePlugin
                ) {
                    keys.insert(ReferenceKey(resolved: id))
                }
            }
        }
        return keys
    }

    private static func start(_ quest: Quest, key: ReferenceKey, engine: SweepEngine) -> [String] {
        var problems: [String] = []
        var started = false
        let state = { attempt { try engine.questRuntime.state(of: quest.formID) } }
        // Another quest's script may have started this one already, through its own queue.
        let startedEarlier = state()?.isRunning == true
        let met = engine.fallbacksMet {
            do {
                started = try engine.bridge.startQuest(for: key)
            } catch let QuestError.aliasFillFailed(_, aliases) {
                for id in aliases {
                    let fill = quest.alias(id: id)?.fillType.name ?? "unknown alias"
                    problems.append("alias does not fill (\(fill))")
                }
            } catch {
                problems.append("start fails: \(error)")
            }
        }
        problems += met.filter { $0.hasPrefix("fault ") || $0.hasPrefix("failed native ") }
            .compactMap(HeadlessSweepReport.fragmentProblem)
            .map { "stage fragment error: \($0)" }
        guard started else { return problems }
        if
            let startUp = quest.stages.first(where: { $0.flags.contains(.startUpStage) }),
            state()?.isStageDone(startUp.index) != true
        {
            problems.append(startedEarlier
                ? "first stage not reached (started earlier by a script)"
                : "first stage not reached")
        }
        return problems
    }

    /// A scene that begins with its quest needs every actor alias that is not optional.
    private static func sceneProblems(
        _ scene: Scene, quest: Quest, engine: SweepEngine
    ) -> [String] {
        guard attempt({ try engine.questRuntime.state(of: quest.formID) })?.isRunning == true
        else { return [] }
        return scene.actors.compactMap { actor in
            guard
                !actor.isOptional, let id = UInt32(exactly: actor.aliasID),
                engine.questRuntime.aliasReference(alias: id, in: quest.formID) == nil
            else { return nil }
            return "scene cannot start: actor alias empty"
        }
    }
}
