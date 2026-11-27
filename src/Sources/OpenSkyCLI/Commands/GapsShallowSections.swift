// The `shallow` section: the handlers that exist but do no work, ranked by how often the
// data uses them (docs/tools/gaps.md, "Shallow handlers").

import Foundation
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgression
import OpenSkyScripting
import OpenSkyScriptingInterface

extension GapsGatherer {
    func shallow() throws -> [GapSection] {
        guard let list = shallowHandlers else {
            throw CLIError.usage("the shallow section needs --shallow-handlers")
        }
        let loader = PexScriptLoader(fileSystem: fileSystem)
        let files = loader.scriptPaths().compactMap { try? loader.load($0) }
        let census = PexNativeCensus(files: files)
        let natives = list.gaps(.native, uses: Dictionary(
            census.referenceCounts.map { ($0.key.name, $0.value) }, uniquingKeysWith: +
        ))
        var conditionCensus = ConditionFunctionCensus()
        var skipped = SkippedRecords()
        for plugin in try requirePlugins().plugins {
            ESMWalk.forEachRecord(in: plugin.file) { record in
                if let fields = try? record.fields() {
                    conditionCensus.record(fields: fields)
                }
                return true
            }
        }
        let conditionUses = Dictionary(conditionCensus.counts.map { index, count in
            (ConditionFunctionNames.name(for: index) ?? "function \(index)", count)
        }, uniquingKeysWith: +)
        let conditions = list.gaps(.condition, uses: conditionUses)
        let perks = plugins.decodeRecords(of: "PERK", skipped: &skipped) {
            try Perk(record: $0, localized: $1)
        }
        let perkCensus = PerkGapCensus(perks: perks)
        let shallowPerks = perkCensus.shallowFunctions
        let note = "done means the body does work; shallow means it answers a constant and "
            + "does nothing else"
        return [
            natives.section("Shallow Papyrus natives", unit: "natives", uses: "call sites", note),
            conditions.section(
                "Shallow condition functions", unit: "functions", uses: "conditions", note
            ),
            GapSection(
                title: "Shallow perk functions",
                unit: "functions",
                done: perkCensus.computedFunctionCount - shallowPerks.count,
                left: shallowPerks,
                usesUnit: "perk effects",
                notes: ["shallow means the result changes with neither the value nor the payload"]
            )
        ]
    }
}

extension ShallowHandlerList.Gaps {
    fileprivate func section(
        _ title: String, unit: String, uses: String, _ note: String
    ) -> GapSection {
        GapSection(
            title: title, unit: unit, done: done, left: left, usesUnit: uses,
            notes: [note] + onPurpose.map { "shallow on purpose, \($0)" }
        )
    }
}
