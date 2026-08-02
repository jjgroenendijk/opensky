// Env-gated QUST sweep over the user's own Skyrim SE install (read-only
// external input, never committed — AGENTS.md Legal & IP): decodes every QUST
// in Skyrim.esm, asserts the count and link invariants, and writes the M13
// target-quest census to gitignored logs/.
//
// The census is the deliverable, not a by-product. M13 picks its target quest
// from real data the way M11 picked its demo activator from the script census:
// the shortlist below ranks quests by how little they need that OpenSky does
// not have yet — condition functions outside
// `ConditionFunctionRegistry.standard`, alias fill types the runtime cannot
// perform, and stage scripts with no fragment table. Coverage numbers are
// asserted as well as printed, because print() never reaches the .xcresult.
//
// Skips automatically when OPENSKY_DATA_ROOT is unset or unresolvable (CI has
// no game data). Run with `make realtest`.
//
// Layouts: UESP "Skyrim Mod:Mod File Format/QUST" and the "QUST Records"
// section of "/VMAD Field"; xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas
// `wbRecord(QUST, ...)` line 8759 and `wbVMADFragmentedQUST` line 2929.

import Foundation
@testable import opensky
import Testing

struct QuestRealDataTests {
    /// Real data only when explicitly pointed at via the env var; the
    /// locator's Steam-default fallback is deliberately not consulted so
    /// machines without the override skip deterministically.
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func sweepsEveryQuestInSkyrimESM() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let header = try file.pluginHeader()

        var census = QuestCensus()
        var quests: [Quest] = []
        guard let top = file.topGroup(of: "QUST"), let children = try? top.children() else {
            Issue.record("Skyrim.esm has no QUST top group")
            return
        }
        for case let .record(record) in children where record.type == "QUST" {
            census.records += 1
            do {
                let quest = try Quest(record: record, localized: header.isLocalized)
                quests.append(quest)
                census.record(quest)
            } catch {
                census.failures[String(describing: error), default: 0] += 1
            }
        }

        #expect(census.records > 0, "no QUST records in Skyrim.esm")
        #expect(census.failures.isEmpty, "QUST decode failures: \(census.failures)")
        try check(census: census, quests: quests)

        let store = QuestStore(file: file, pluginName: "Skyrim.esm")
        #expect(store.count == quests.count, "the store lost quests the sweep decoded")
        #expect(store.skippedRecordCount == 0, "the store skipped a QUST the sweep decoded")

        let report = census.report()
        print(report)
        try FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )
        try report.write(to: logURL, atomically: true, encoding: .utf8)
    }

    /// The invariants that would break first if the grouping state machine
    /// mis-attributed a subrecord, plus the coverage numbers the milestone
    /// chooses its target quest against.
    private func check(census: QuestCensus, quests: [Quest]) throws {
        checkExactSkyrimCounts(census)

        // The only subrecords dropped are the three the Creation Kit wrote in
        // an earlier version and xEdit marks unused (`wbUnused(SCHR/SCTX/QNAM)`
        // under 'Log Entry', wbDefinitionsTES5.pas line 8820). Anything else in
        // the tally is a layout the decoder does not really understand.
        #expect(census.skipped.ranked.map(\.name).sorted() == [
            "unknown QNAM", "unknown SCHR", "unknown SCTX"
        ], "unexpected QUST subrecords were dropped: \(census.skipped.ranked)")
        #expect(census.fragmentTailFailures == 0, "a QUST VMAD fragment tail failed to decode")

        // Every objective target names an alias its quest defines, and every
        // fragment names a stage its quest declares. Both would break
        // immediately if a marker subrecord were grouped under a wrong parent,
        // which is what makes them the real proof the state machine is right.
        #expect(census.targetsWithUnknownAlias == 0, "objective target names no declared alias")
        #expect(census.fragmentsWithUnknownStage == 0, "fragment names no declared stage")
        #expect(census.aliasScriptsOnOtherQuests == 0, "alias script section names another quest")

        // Alias IDs are unique within a quest, which is what makes
        // `Quest.alias(id:)` a lookup rather than a search.
        #expect(census.duplicateAliasIDs == 0, "a quest declares the same alias ID twice")

        let registry = ConditionFunctionRegistry.standard
        let fraction = census.coverage.coverageFraction(in: registry)
        #expect(fraction > 0, "the registry answers none of the quest conditions")
        #expect(fraction < 1, "quest conditions claim a complete registry")
        #expect(!census.shortlist.isEmpty, "no quest is a viable M13 target")
        #expect(quests.count == census.records)
    }

    /// The census numbers this milestone's target-quest choice rests on. They
    /// are pinned rather than only printed, because a silent drift in any of
    /// them would change which quests the shortlist offers.
    private func checkExactSkyrimCounts(_ census: QuestCensus) {
        #expect(census.records == 1811)
        #expect(census.stages == 5220)
        #expect(census.journalStages == 726)
        #expect(census.logEntries == 5294)
        #expect(census.logEntriesWithText == 771)
        #expect(census.objectives == 1452)
        #expect(census.targets == 1808)
        #expect(census.legacyTargets == 0)
        #expect(census.aliases == 12891)
        #expect(census.aliasCategories == ["reference": 11999, "location": 892])
        #expect(census.questsWithFragments == 856)
        #expect(census.fragments == 5108)
        #expect(census.aliasScriptSections == 2149)
        #expect(census.coverage.total == 11427)
        #expect(census.coverage.distinctIndices == 90)
        // Every alias fill type the decoder models is exercised by vanilla
        // data, which is what proves the union is read the way xEdit reads it.
        #expect(census.fillTypes.count == 10)
        #expect(census.fillTypes["unique actor"] == 2900)
        #expect(census.fillTypes["specific reference"] == 2687)
        #expect(census.fillTypes["none"] == 2062)
    }

    /// logs/quest-census.log (gitignored) next to the other real-data sidecars.
    private var logURL: URL {
        logsDirectory.appending(path: "quest-census.log")
    }

    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // openskyTests/
            .deletingLastPathComponent() // repo root
            .appending(path: "logs")
    }
}
