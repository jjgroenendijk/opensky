// `openskycli sweep rules`: checks the rules vanilla data implies and reports each
// violation under its rule (docs/tools/headless-sweeps.md, "Rule sweep").

import Foundation
import OpenSkyAIPackages
import OpenSkyCLIArguments
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScripting

enum SweepRulesCommand {
    struct Rule {
        let id: String
        /// Why vanilla data must satisfy it.
        let reason: String
        let check: @MainActor (Inputs, inout HeadlessSweepReport) -> Void
    }

    struct Inputs {
        let plugins: LoadOrderPlugins
        let data: SweepRuleData
    }

    static let rules: [Rule] = [
        Rule(
            id: "npc-package",
            reason: "A placed unique NPC stands in the world all day, so some AI package of "
                + "its own, from its template, from its default list, or from a quest alias "
                + "runs it.",
            check: npcPackages
        ),
        Rule(
            id: "load-door-navmesh",
            reason: "The player and followers arrive at a load door's far side and walk on, "
                + "so the cell there has a navmesh.",
            check: loadDoorNavmesh
        ),
        Rule(
            id: "leveled-list",
            reason: "The game rolls a leveled list to place an item, an actor, or a spell, "
                + "so every entry names a record that exists. An empty list is allowed: "
                + "vanilla rolls some to give nothing.",
            check: leveledLists
        ),
        Rule(
            id: "topic-info",
            reason: "A topic is said through one of its infos, so a topic with infos has "
                + "one whose conditions can pass. A topic with none is never said.",
            check: topicInfos
        ),
        Rule(
            id: "placed-base",
            reason: "Every placed reference shows its base object, so the base exists and is "
                + "of a type the engine builds into a cell.",
            check: placedBases
        )
    ]

    static func run(context: CLIContext, arguments: SweepArguments.Rules) throws {
        let plugins = try context.loadOrder().plugins
        let inputs = Inputs(plugins: plugins, data: SweepRuleData(plugins: plugins))
        var text = ""
        var summary = ""
        for rule in rules {
            var report = HeadlessSweepReport()
            rule.check(inputs, &report)
            let body = report.text(unit: "records", limit: nil, examples: arguments.report.examples)
            text += "## \(rule.id)\n\(rule.reason)\n\(body)\n"
            let shown = report.text(
                unit: "records",
                limit: arguments.report.limit,
                examples: arguments.report.examples
            )
            summary += "## \(rule.id)\n\(shown)\n"
        }
        let directory: URL
        if let out = arguments.report.out {
            directory = URL(filePath: out, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } else {
            directory = try RunDirectory.create("sweep-rules")
        }
        try text.write(
            to: directory.appending(path: "report.txt"),
            atomically: true,
            encoding: .utf8
        )
        print(summary, terminator: "")
        print("[INFO] report: \(directory.path(percentEncoded: false))")
    }

    /// Placed base types the engine builds: the model bases, statics, decals, lights,
    /// sounds, addon nodes, and for a placed actor its NPC or leveled NPC.
    static let builtBaseTypes = ModelBase.supportedTypes
        .union(["STAT", "TXST", "LIGH", "SOUN", "ADDN"])
    static let builtActorTypes: Set<FourCC> = ["NPC_", "LVLN"]

    private static func npcPackages(_ inputs: Inputs, _ report: inout HeadlessSweepReport) {
        let store = PackageStore(loadOrder: inputs.plugins)
        var skipped = SkippedRecords()
        let actors = inputs.plugins
            .decodeRecords(of: "NPC_", skipped: &skipped) { record, localized in
                try ActorBase(record: record, localized: localized)
            }
        let quests = QuestStore(plugins: inputs.plugins.files).sortedQuests()
        let aliased = Set(quests.flatMap(\.aliases).filter { !$0.packages.isEmpty }
            .compactMap(\.uniqueActor?.rawValue))
        let placed = Set(inputs.data.placed.values.filter(\.isActor).map(\.base))
        for actor in actors
            where actor.flags.contains(.unique) && placed.contains(actor.formID.rawValue)
        {
            report.noteRun()
            let name = inputs.data.name(actor.formID.rawValue)
            guard !aliased.contains(actor.formID.rawValue) else { continue }
            guard let lists = attempt({ try store.packageLists(for: actor.formID) }) else {
                report.note("npc-package: the template chain does not resolve", subject: name)
                continue
            }
            let runnable = (lists.own + lists.defaults).compactMap(store.package)
                .filter { (-1 ... 23).contains($0.schedule.hour) }
            if runnable.isEmpty {
                let problem = lists.own.isEmpty && lists.defaults.isEmpty
                    ? "no package" : "no package resolves to a runnable PACK"
                report.note("npc-package: \(problem)", subject: name)
            }
        }
    }

    private static func loadDoorNavmesh(_ inputs: Inputs, _ report: inout HeadlessSweepReport) {
        let data = inputs.data
        for id in data.placed.keys.sorted() {
            guard let destination = data.placed[id]?.destination else { continue }
            report.noteRun()
            let subject = SweepRuleData.hex(id)
            guard let far = data.placed[destination] else {
                report.note(
                    "load-door-navmesh: the destination door does not exist",
                    subject: subject
                )
                continue
            }
            guard let cell = data.standingCell(far) else {
                report.note("load-door-navmesh: the destination door has no cell", subject: subject)
                continue
            }
            if !data.navmeshCells.contains(cell) {
                report.note(
                    "load-door-navmesh: no navmesh",
                    subject: "\(subject) to \(data.name(cell))"
                )
            }
        }
    }

    private static func leveledLists(_ inputs: Inputs, _ report: inout HeadlessSweepReport) {
        var skipped = SkippedRecords()
        var entries: [UInt32: [UInt32]] = [:]
        for type in LeveledList.recordTypes.sorted(by: { $0.description < $1.description }) {
            for list in inputs.plugins.decodeRecords(of: type, skipped: &skipped, using: {
                try LeveledList(record: $0)
            }) {
                entries[list.formID.rawValue] = list.entries.map(\.reference.rawValue)
                report.noteRun()
            }
        }
        let types = inputs.data.types
        for (id, targets) in entries.sorted(by: { $0.key < $1.key })
            where targets.contains(where: { types[$0] == nil })
        {
            report.note("leveled-list: an entry names no record", subject: inputs.data.name(id))
        }
    }

    private static func topicInfos(_ inputs: Inputs, _ report: inout HeadlessSweepReport) {
        let dialogue = DialogueStore(plugins: inputs.plugins.files)
        for topic in dialogue.sortedTopics() {
            report.noteRun()
            let name = topic.editorID ?? topic.formID.description
            let infos = dialogue.infos(for: topic.formID)
            if
                !infos.isEmpty,
                infos.allSatisfy({ VanillaDataRules.contradicts($0.conditions.conditions) })
            {
                report.note("topic-info: every info's conditions contradict", subject: name)
            }
        }
    }

    private static func placedBases(_ inputs: Inputs, _ report: inout HeadlessSweepReport) {
        let data = inputs.data
        for id in data.placed.keys.sorted() {
            guard let reference = data.placed[id] else { continue }
            report.noteRun()
            let subject = SweepRuleData.hex(id)
            guard let type = data.types[reference.base] else {
                report.note("placed-base: the base does not exist", subject: subject)
                continue
            }
            let built = reference.isActor ? builtActorTypes : builtBaseTypes
            if !built.contains(type) {
                report.note("placed-base: base type \(type) is not built", subject: subject)
            }
        }
    }
}
