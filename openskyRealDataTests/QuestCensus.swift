// Accumulator and report for the vanilla QUST sweep (QuestRealDataTests).
//
// It answers two questions at once. The invariant half proves the grouping
// state machine attributed every subrecord to the right parent: targets that
// name a declared alias, fragments that name a declared stage, alias IDs that
// are unique within their quest. The census half is the M13 target-quest
// shortlist evidence — per-quest size, alias fill types, and how much of each
// quest's condition traffic `ConditionFunctionRegistry.standard` can already
// answer.

import Foundation
@testable import opensky

struct QuestCensus {
    /// One quest reduced to the numbers the shortlist ranks on.
    struct Entry {
        let editorID: String
        let formID: FormID
        let kind: String
        let stages: Int
        let journalStages: Int
        let objectives: Int
        let targets: Int
        let aliases: Int
        let fragments: Int
        let conditions: Int
        let unimplementedConditions: Int
        let fillTypes: [String]

        /// Cheapest-first ordering: a quest OpenSky can already evaluate every
        /// condition of, with the fewest moving parts, is the easiest target.
        var difficulty: Int {
            unimplementedConditions * 100 + stages + objectives + aliases * 2
        }
    }

    var records = 0
    var failures: [String: Int] = [:]
    var stages = 0
    var journalStages = 0
    var logEntries = 0
    var logEntriesWithText = 0
    var objectives = 0
    var targets = 0
    var aliases = 0
    var fragments = 0
    var aliasScriptSections = 0
    var questsWithFragments = 0
    var fragmentTailFailures = 0
    var targetsWithUnknownAlias = 0
    var fragmentsWithUnknownStage = 0
    var aliasScriptsOnOtherQuests = 0
    var duplicateAliasIDs = 0
    var legacyTargets = 0
    var kinds: [String: Int] = [:]
    var fillTypes: [String: Int] = [:]
    var aliasCategories: [String: Int] = [:]
    var fragmentFunctions: [String: Int] = [:]
    var fragmentScripts: Set<String> = []
    var coverage = ConditionCoverage()
    var skipped = QuestTally()
    var entries: [Entry] = []

    mutating func record(_ quest: Quest) {
        skipped.merge(quest.skipped)
        kinds[quest.kind.name, default: 0] += 1
        if quest.script.skipped.counts[.fragments("QUST")] != nil {
            fragmentTailFailures += 1
        }
        recordStages(quest)
        recordObjectives(quest)
        recordAliases(quest)
        recordFragments(quest)
        entries.append(entry(for: quest))
    }

    private mutating func recordStages(_ quest: Quest) {
        stages += quest.stages.count
        journalStages += quest.journalStages.count
        for stage in quest.stages {
            logEntries += stage.logEntries.count
            logEntriesWithText += stage.logEntries.count { $0.text != nil }
            for entry in stage.logEntries {
                entry.conditions.conditions.forEach { coverage.record($0) }
            }
        }
    }

    private mutating func recordObjectives(_ quest: Quest) {
        objectives += quest.objectives.count
        legacyTargets += quest.legacyTargets.count
        let declared = Set(quest.aliases.map { Int32(bitPattern: $0.id) })
        for objective in quest.objectives {
            targets += objective.targets.count
            for target in objective.targets {
                // -1 is the documented "no alias" spelling and is not a link.
                if target.aliasID != -1, !declared.contains(target.aliasID) {
                    targetsWithUnknownAlias += 1
                }
                target.conditions.conditions.forEach { coverage.record($0) }
            }
        }
        quest.dialogueConditions.conditions.forEach { coverage.record($0) }
        quest.storyManagerConditions.conditions.forEach { coverage.record($0) }
    }

    private mutating func recordAliases(_ quest: Quest) {
        aliases += quest.aliases.count
        var seen: Set<UInt32> = []
        for alias in quest.aliases {
            if !seen.insert(alias.id).inserted {
                duplicateAliasIDs += 1
            }
            fillTypes[alias.fillType.name, default: 0] += 1
            aliasCategories["\(alias.category)", default: 0] += 1
            alias.matchConditions.conditions.forEach { coverage.record($0) }
        }
    }

    private mutating func recordFragments(_ quest: Quest) {
        guard let section = quest.script.questFragments else { return }
        questsWithFragments += 1
        fragments += section.fragments.count
        aliasScriptSections += section.aliasScripts.count
        fragmentScripts.insert(section.fileName)
        let declaredStages = Set(quest.stages.map(\.index))
        for fragment in section.fragments {
            fragmentFunctions[fragment.functionName, default: 0] += 1
            if !declaredStages.contains(fragment.stageIndex) {
                fragmentsWithUnknownStage += 1
            }
        }
        for alias in section.aliasScripts where alias.object.formID != quest.formID {
            aliasScriptsOnOtherQuests += 1
        }
    }

    private func entry(for quest: Quest) -> Entry {
        var conditions = 0
        var unimplemented = 0
        let registry = ConditionFunctionRegistry.standard
        for condition in allConditions(of: quest) {
            conditions += 1
            if registry[condition.functionIndex] == nil {
                unimplemented += 1
            }
        }
        return Entry(
            editorID: quest.editorID ?? quest.formID.description,
            formID: quest.formID,
            kind: quest.kind.name,
            stages: quest.stages.count,
            journalStages: quest.journalStages.count,
            objectives: quest.objectives.count,
            targets: quest.objectives.reduce(0) { $0 + $1.targets.count },
            aliases: quest.aliases.count,
            fragments: quest.fragments.count,
            conditions: conditions,
            unimplementedConditions: unimplemented,
            fillTypes: Set(quest.aliases.map(\.fillType.name)).sorted()
        )
    }

    private func allConditions(of quest: Quest) -> [Condition] {
        var all = quest.dialogueConditions.conditions
        all += quest.storyManagerConditions.conditions
        all += quest.stages.flatMap { $0.logEntries.flatMap(\.conditions.conditions) }
        all += quest.objectives.flatMap { $0.targets.flatMap(\.conditions.conditions) }
        all += quest.aliases.flatMap(\.matchConditions.conditions)
        return all
    }

    /// Quests that could carry the M13 slice: they show a journal entry, have
    /// at least one objective and one stage fragment to drive it, and need no
    /// condition function OpenSky has not implemented.
    var shortlist: [Entry] {
        entries
            .filter {
                $0.unimplementedConditions == 0
                    && $0.journalStages > 0
                    && $0.objectives > 0
                    && $0.fragments > 0
            }
            .sorted { ($0.difficulty, $0.editorID) < ($1.difficulty, $1.editorID) }
    }

    func report() -> String {
        let shortlist = shortlist
        let registry = ConditionFunctionRegistry.standard
        let fraction = coverage.coverageFraction(in: registry)
        let misses = coverage.rankedUnimplemented(in: registry).prefix(10)
            .map { "\($0.index):\($0.conditions)" }
            .joined(separator: " ")
        return """
        [INFO] Skyrim.esm QUST census: \(records) quests decoded, \
        \(failures.count) failures, \(skipped.total) subrecords skipped
        [INFO] stages \(stages) (\(journalStages) with journal text), \
        log entries \(logEntries) (\(logEntriesWithText) with CNAM text)
        [INFO] objectives \(objectives), objective targets \(targets), \
        record-level legacy targets \(legacyTargets)
        [INFO] aliases \(aliases) \(render(aliasCategories)); \
        duplicate alias IDs \(duplicateAliasIDs)
        [INFO] alias fill types: \(render(fillTypes))
        [INFO] fragment tables \(questsWithFragments) over \(fragmentScripts.count) \
        distinct QF scripts, \(fragments) stage fragments, \
        \(aliasScriptSections) alias script sections, \
        \(fragmentTailFailures) tails lost
        [INFO] distinct fragment function names: \(fragmentFunctions.count)
        [INFO] quest types: \(render(kinds))
        [INFO] condition demand: \(coverage.total) conditions over \
        \(coverage.distinctIndices) distinct raw indices, \
        \(String(format: "%.1f%%", fraction * 100)) answerable by the registry
        [INFO] hottest unimplemented raw indices: \(misses)
        [INFO] link invariants: targets naming no declared alias \
        \(targetsWithUnknownAlias), fragments naming no declared stage \
        \(fragmentsWithUnknownStage), alias script sections on another quest \
        \(aliasScriptsOnOtherQuests)

        [INFO] M13 target-quest shortlist (\(shortlist.count) candidates need no \
        unimplemented condition function, show journal text, and carry stage fragments)
        \(shortlistTable(shortlist))
        """
    }

    private func shortlistTable(_ shortlist: [Entry]) -> String {
        let header = "  editorID | formID | type | stages | objectives | aliases | "
            + "fragments | conditions | fill types"
        let rows = shortlist.prefix(25).map { entry in
            "  \(entry.editorID) | \(entry.formID) | \(entry.kind) | "
                + "\(entry.stages) | \(entry.objectives) | \(entry.aliases) | "
                + "\(entry.fragments) | \(entry.conditions) | "
                + entry.fillTypes.joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private func render(_ histogram: [String: Int]) -> String {
        histogram.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: " ")
    }
}
