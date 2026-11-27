// `openskycli sweep fragments`: runs every script fragment headless, one at a time, and
// ranks the problems they meet (docs/tools/headless-sweeps.md, "Fragment sweep").

import Foundation
import OpenSkyCLIArguments
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScripting

@MainActor
enum SweepFragmentsCommand {
    static func run(context: CLIContext, arguments: SweepArguments.Fragments) throws {
        let engine = try SweepEngine(context: context)
        var report = HeadlessSweepReport()
        let note = { (subject: String, met: [String]) in
            report.noteRun()
            for problem in met.compactMap(HeadlessSweepReport.fragmentProblem) {
                report.note(problem, subject: subject)
            }
        }
        for (phase, run) in [
            ("quest stage", questFragments), ("topic info", topicInfoFragments),
            ("scene", sceneFragments), ("package", packageFragments)
        ] as [(String, (SweepEngine, Note) -> Void)] {
            FileHandle.standardError.write(Data("[INFO] sweep: \(phase) fragments\n".utf8))
            run(engine, note)
        }
        let examples = arguments.report.examples
        let text = report.text(unit: "fragments", limit: nil, examples: examples)
        let directory = try engine.write(
            report: text,
            name: "sweep-fragments",
            out: arguments.report.out
        )
        print(
            report.text(unit: "fragments", limit: arguments.report.limit, examples: examples),
            terminator: ""
        )
        print("[INFO] report and fallbacks.tsv: \(directory.path(percentEncoded: false))")
    }

    typealias Note = (String, [String]) -> Void

    /// Each stage's fragments, on the quest's own script instance.
    private static func questFragments(_ engine: SweepEngine, _ note: Note) {
        for quest in engine.quests.sortedQuests() where !quest.fragments.isEmpty {
            guard let key = engine.quests.key(for: quest.formID) else { continue }
            engine.bridge.attachScripts(ofQuest: quest.formID)
            let name = quest.editorID ?? quest.formID.description
            for stage in Set(quest.fragments.map(\.stageIndex)).sorted() {
                var queued = 0
                var met = engine.fallbacksMet {
                    queued = engine.world.queueStageFragments(of: quest, stage: stage, key: key)
                }
                if queued == 0 {
                    met.append("fragment does not queue")
                }
                note("\(name) stage \(stage)", met)
            }
        }
    }

    /// Begin and end fragments of every INFO, with its topic's quest as the owning quest.
    private static func topicInfoFragments(_ engine: SweepEngine, _ note: Note) {
        let dialogue = DialogueStore(plugins: engine.plugins.files)
        for topic in dialogue.sortedTopics() {
            let quest = topic.owningQuest.flatMap(engine.key(of:))
            for info in dialogue.infos(for: topic.formID) {
                guard let key = dialogue.key(forInfo: info.formID) else { continue }
                for phase in [TopicInfoFragmentPhase.begin, .end]
                    where info.script.infoFragments?.fragment(phase) != nil
                {
                    var ran: [String] = []
                    var met = engine.fallbacksMet {
                        ran = engine.bridge.dialogueFragments.runTopicInfoFragments(
                            of: info, key: key, phase: phase,
                            context: TopicInfoFragmentContext(speaker: nil, quest: quest)
                        )
                    }
                    if ran.isEmpty {
                        met.append("fragment does not queue")
                    }
                    note("INFO \(info.formID) \(phase)", met)
                }
            }
        }
    }

    private static func sceneFragments(_ engine: SweepEngine, _ note: Note) {
        for entry in SceneStore(plugins: engine.plugins.files).scenes.records {
            let scene = entry.record
            guard let section = scene.scriptData.recordFragments else { continue }
            let key = ReferenceKey(resolved: entry.id)
            let name = scene.editorID ?? scene.formID.description
            let functions = section.fragments.map { ($0.scriptName, $0.functionName) }
                + section.phaseFragments.map { ($0.scriptName, $0.functionName) }
            for (script, function) in functions {
                var ran = false
                var met = engine.fallbacksMet {
                    ran = engine.bridge.sceneFragments.runSceneFragment(
                        of: scene, key: key,
                        scriptName: script.isEmpty ? section.fileName : script,
                        functionName: function
                    )
                }
                if !ran {
                    met.append("fragment does not queue")
                }
                note("\(name) \(function)", met)
            }
        }
    }

    /// Start, end, and change fragments, run with the player as the package's actor.
    private static func packageFragments(_ engine: SweepEngine, _ note: Note) {
        var skipped = SkippedRecords()
        let packages = engine.plugins.decodeRecords(of: "PACK", skipped: &skipped) {
            try PackageDecoder.decode($0)
        }
        for package in packages {
            guard let section = package.scriptData.recordFragments else { continue }
            let name = package.editorID ?? package.formID.description
            for fragment in section.fragments {
                var ran = false
                var met = engine.fallbacksMet {
                    ran = engine.bridge.runPackageFragment(
                        of: package, slot: fragment.slot, actor: .player
                    )
                }
                if !ran {
                    met.append("fragment does not queue")
                }
                note("\(name) slot \(fragment.slot)", met)
            }
        }
    }
}
