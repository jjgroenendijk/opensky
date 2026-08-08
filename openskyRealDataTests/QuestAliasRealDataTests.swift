// Env-gated acceptance for issue #183 over the user's own install: the
// census-chosen target quest's aliases fill against real data, and a corpus
// sweep says how much of vanilla each stated deferral actually affects.
//
// The target quest is `MGRArniel01`, the cheapest entry on the 13.1 census
// shortlist (docs/formats/records.md): one forced-reference alias, which is the
// one fill type item 13.4 implements. Named here rather than rediscovered,
// because the shortlist is the record of that choice.
//
// Nothing from the install is committed: the report goes to gitignored `logs/`
// and carries counts, alias names, fill types and editor IDs only — never
// journal text and never a script body. Run it with
// `make realtest T='QuestAliasRealDataTests/fillsTheTargetQuestsAliases()'`,
// which supplies the data root and the RSS watchdog.

import Foundation
@testable import opensky
import Testing

struct QuestAliasRealDataTests {
    private static let targetEditorID = "MGRArniel01"

    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil)) @MainActor
    func fillsTheTargetQuestsAliases() throws {
        let root = try #require(Self.dataRoot)
        let pluginName = "Skyrim.esm"
        let file = try ESMFile(url: root.dataURL.appending(path: pluginName))
        let quests = QuestStore(file: file, pluginName: pluginName)
        let quest = try #require(quests.quest(editorID: Self.targetEditorID))

        // The target quest itself: every non-optional alias fills, so the quest
        // is allowed to start.
        let target = QuestAliasFiller.fill(quest, resolver: quests.resolver)
        #expect(target.canStartQuest)
        #expect(target.unfilledRequired.isEmpty)
        #expect(target.state.count == quest.aliases.count)
        #expect(target.skipped.isEmpty)

        // Filling it through the runtime writes the same table and lets the
        // quest start, which is the path a session actually takes.
        let worldState = WorldStateStore()
        let runtime = QuestRuntime(store: worldState, quests: quests)
        try runtime.startQuest(quest.formID)
        #expect(try runtime.aliasState(of: quest.formID) == target.state)
        #expect(try runtime.state(of: quest.formID).isRunning)

        let census = Self.census(quests: quests)
        // The corpus is what makes the deferrals measurable rather than
        // described: every alias is either filled or counted under a reason.
        // The two do not partition the set, because a "Force Into Alias When
        // Filled" target is counted as skipped for its own (absent) fill type
        // and then filled by its source — so the sum is a cover, not a split.
        #expect(census.filled + census.skipped.total >= census.aliases)
        #expect(census.filled <= census.aliases)
        #expect(census.aliases > 0)

        let report = Self.report(quest: quest, result: target, census: census)
        print(report)
        let logs = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
        try FileManager.default.createDirectory(
            at: logs, withIntermediateDirectories: true
        )
        try report.write(
            to: logs.appending(path: "quest-alias-probe.log"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// Corpus totals over every QUST record the plugin defines.
    private struct Census {
        var quests = 0
        var questsWithAliases = 0
        var aliases = 0
        var filled = 0
        var skipped = QuestAliasTally()
        /// Quests an implemented fill type would stop from starting.
        var blockedQuests: [String] = []
    }

    /// Runs the fill pass over every quest, which is cheap: a forced-reference
    /// fill is a dictionary lookup and nothing touches the world.
    private static func census(quests: QuestStore) -> Census {
        var census = Census()
        for quest in quests.sortedQuests() {
            census.quests += 1
            guard !quest.aliases.isEmpty else { continue }
            census.questsWithAliases += 1
            census.aliases += quest.aliases.count
            let result = QuestAliasFiller.fill(quest, resolver: quests.resolver)
            census.filled += result.state.count
            census.skipped.merge(result.skipped)
            if !result.canStartQuest {
                census.blockedQuests.append(quest.editorID ?? quest.formID.description)
            }
        }
        return census
    }

    /// Counts, alias names, fill types and editor IDs only.
    private static func report(
        quest: Quest,
        result: QuestAliasFillResult,
        census: Census
    ) -> String {
        var lines = [
            "OpenSky quest alias probe (issue #183)",
            "target: \(quest.editorID ?? "unnamed") aliases \(quest.aliases.count) "
                + "filled \(result.state.count) skipped \(result.skipped.total)"
        ]
        for alias in quest.aliases {
            let fill = result.state.reference(forAlias: alias.id)?.description ?? "empty"
            lines.append(
                "  [\(alias.id)] \(alias.name ?? "unnamed") "
                    + "(\(alias.fillType.name)"
                    + "\(alias.flags.contains(.optional) ? ", optional" : "")) -> \(fill)"
            )
        }
        lines.append(
            "corpus: quests \(census.quests) with aliases \(census.questsWithAliases) "
                + "aliases \(census.aliases) filled \(census.filled)"
        )
        for entry in census.skipped.ranked {
            let share = Double(entry.count) / Double(max(census.aliases, 1)) * 100
            lines.append(
                "  skip \(entry.name) \(entry.count) "
                    + "(\(String(format: "%.2f", share))% of aliases)"
            )
        }
        lines.append("blocked quests: \(census.blockedQuests.count)")
        for editorID in census.blockedQuests.prefix(10) {
            lines.append("  blocked \(editorID)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
