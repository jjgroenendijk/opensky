// QUST sweep over `Skyrim.esm`: count and link invariants, plus a target-quest
// census in `.logs/` that ranks quests by what OpenSky still lacks (condition
// functions, alias fill types, stage scripts without fragments). Coverage is
// asserted, because print() never reaches the .xcresult. Layout: UESP "QUST"
// and "VMAD Field", and xEdit `wbRecord(QUST, ...)` and `wbVMADFragmentedQUST`.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyWorldConditions
import Testing

struct QuestRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func sweepsEveryQuestInSkyrimESM() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
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

        // Anything in the tally is a layout the decoder does not understand.
        #expect(
            census.skipped.ranked.isEmpty,
            "QUST subrecords were dropped: \(census.skipped.ranked)"
        )
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
        #expect(fraction == 1, "a quest condition names a function the registry lacks")
        #expect(!census.shortlist.isEmpty, "no quest is a viable M13 target")
        #expect(quests.count == census.records)
    }

    /// The census numbers this milestone's target-quest choice rests on. They
    /// are pinned rather than only printed, because a silent drift in any of
    /// them would change which quests the shortlist offers.
    private func checkExactSkyrimCounts(_ census: QuestCensus) {
        #expect(ContentCount.isNear(census.records, 1811))
        #expect(ContentCount.isNear(census.stages, 5220))
        #expect(ContentCount.isNear(census.journalStages, 726))
        #expect(ContentCount.isNear(census.logEntries, 5294))
        #expect(ContentCount.isNear(census.logEntriesWithText, 771))
        #expect(ContentCount.isNear(census.objectives, 1452))
        #expect(ContentCount.isNear(census.targets, 1808))
        #expect(census.legacyTargets == 0)
        #expect(ContentCount.isNear(census.aliases, 12891))
        #expect(census.aliasCategories == ["reference": 11999, "location": 892])
        #expect(ContentCount.isNear(census.questsWithFragments, 856))
        #expect(ContentCount.isNear(census.fragments, 5108))
        #expect(ContentCount.isNear(census.aliasScriptSections, 2149))
        #expect(ContentCount.isNear(census.coverage.total, 11427))
        #expect(census.coverage.distinctIndices == 90)
        // Every alias fill type the decoder models is exercised by vanilla
        // data, which is what proves the union is read the way xEdit reads it.
        #expect(census.fillTypes.count == 10)
        #expect(ContentCount.isNear(census.fillTypes["unique actor"] ?? 0, 2900))
        #expect(ContentCount.isNear(census.fillTypes["specific reference"] ?? 0, 2687))
        #expect(ContentCount.isNear(census.fillTypes["none"] ?? 0, 2062))
    }

    /// .logs/quest-census.log (gitignored) next to the other real-data sidecars.
    private var logURL: URL {
        get throws { try logsDirectory.appending(path: "quest-census.log") }
    }

    private var logsDirectory: URL {
        get throws { try RepositoryLogs.directory() }
    }
}
