// Env-gated CTDA sweep over the user's own Skyrim SE install (read-only
// external input, never committed — AGENTS.md Legal & IP): decodes every CTDA
// subrecord of every record in Skyrim.esm, asserts none of them throws, and
// tallies how much of that traffic `ConditionFunctionRegistry.standard` can
// actually evaluate (issue #251). It decodes fields directly rather than
// through per-record wiring, so a record type nobody has modelled yet still
// contributes its conditions. Skips automatically when OPENSKY_DATA_ROOT is
// unset/unresolvable (CI has no game data). Summary and coverage report are
// printed and written to logs/; the coverage numbers are also asserted,
// because print() never reaches the .xcresult.
//
// Coverage model and report text live in `ConditionCoverageTally.swift` and
// `ConditionCoverageReport.swift`.
//
// Layout: UESP "Skyrim Mod:Mod File Format/CTDA Field" and xEdit dev
// Core/wbDefinitionsTES5.pas `wbCTDA` (line 6889).

import Foundation
@testable import opensky
import Testing

struct ConditionRealDataTests {
    /// Real data only when explicitly pointed at via the env var; the
    /// locator's Steam-default fallback is deliberately not consulted so
    /// machines without the override skip deterministically.
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// Raw indices the open sources disagree about, probed for their on-disk
    /// shape. xEdit's TES5 table puts GetRandomPercent at stored 77 while the
    /// older gib.me list implies 76; a no-parameter function compared against
    /// values spread over 0-100 is the one that really is GetRandomPercent.
    private static let disputedIndices: [UInt16] = [76, 77]

    @Test(.enabled(if: Self.dataRoot != nil))
    func sweepsEveryConditionInSkyrimESM() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))

        let stats = sweep(file: file)
        #expect(stats.decoded > 0, "no CTDA subrecords in Skyrim.esm")
        #expect(stats.skipped == 0, "wrong-size CTDA payloads in Skyrim.esm")
        #expect(stats.unreadableRecords == 0, "records whose fields failed to parse")

        let summary = """
        \(stats.summary)
        \(stats.coverage.report(probing: Self.disputedIndices))
        """
        print(summary)
        try? summary.write(to: logURL, atomically: true, encoding: .utf8)
        try check(coverage: stats.coverage, decoded: stats.decoded)
    }

    /// The coverage ratio is the deliverable of this sweep, so it is asserted
    /// rather than only printed: `print()` never reaches the .xcresult, and a
    /// number nobody checks is not evidence.
    private func check(coverage: ConditionCoverage, decoded: Int) throws {
        let registry = ConditionFunctionRegistry.standard
        #expect(coverage.total == decoded, "coverage tally missed conditions")

        let implemented = coverage.implementedCount(in: registry)
        #expect(implemented > 0, "the registry answers none of Skyrim.esm's conditions")
        let fraction = coverage.coverageFraction(in: registry)
        #expect(fraction > 0, "coverage fraction \(fraction) is not above zero")
        #expect(fraction < 1, "coverage fraction \(fraction) claims a complete registry")
        #expect(
            coverage.distinctIndices > registry.count,
            "Skyrim.esm should use far more indices than the registry implements"
        )

        let ranked = coverage.rankedUnimplemented(in: registry)
        let hottest = try #require(ranked.first, "no unimplemented function found")
        #expect(hottest.conditions > 0, "the hottest miss carries no conditions")
        #expect(registry[hottest.index] == nil, "ranked miss is actually implemented")
        let missed = ranked.reduce(0) { $0 + $1.conditions }
        #expect(implemented + missed == coverage.total, "conditions lost between buckets")
        checkDisputedIndices(coverage: coverage)
    }

    /// Pins the GetRandomPercent index to what the plugin actually shows. The
    /// function declares no parameters and returns 0-100, so whichever of the
    /// two candidate indices is really GetRandomPercent leaves both parameter
    /// words zero everywhere and is only ever compared against 0-100.
    private func checkDisputedIndices(coverage: ConditionCoverage) {
        let registry = ConditionFunctionRegistry.standard
        let random = registry.sortedFunctions().first { $0.name == "GetRandomPercent" }
        guard let random else { return }
        guard let shape = coverage.shape(of: random.index) else {
            Issue.record("GetRandomPercent raw index \(random.index) is unused")
            return
        }
        #expect(
            shape.takesNoParameters,
            "raw \(random.index) carries parameters, so it is not GetRandomPercent"
        )
        #expect(
            shape.percentRangeComparisons == shape.literalComparisons,
            "raw \(random.index) is compared outside 0-100"
        )
        #expect(
            (shape.maximumComparison ?? 0) > 1,
            "raw \(random.index) never compares above 1, so it reads as a flag"
        )
    }

    // MARK: - Sweep

    private struct ConditionStats {
        var records = 0
        var recordsWithConditions = 0
        var unreadableRecords = 0
        var decoded = 0
        var skipped = 0
        var countMismatches = 0
        var mismatchHistogram: [String: Int] = [:]
        var useGlobal = 0
        var orFlagged = 0
        var parameterNames = 0
        var operatorHistogram: [String: Int] = [:]
        var runOnHistogram: [String: Int] = [:]
        var recordTypeHistogram: [String: Int] = [:]
        var coverage = ConditionCoverage()
        var nonReferenceGarbage = 0

        var summary: String {
            let operators = ConditionStats.render(operatorHistogram)
            let runOns = ConditionStats.render(runOnHistogram)
            let carriers = recordTypeHistogram.sorted { $0.value > $1.value }
                .prefix(12).map { "\($0.key):\($0.value)" }.joined(separator: " ")
            return """
            [INFO] Skyrim.esm condition sweep: \(decoded) CTDA decoded over \
            \(recordsWithConditions)/\(records) records, \(skipped) skipped, no throws
            [INFO] operator histogram: \(operators)
            [INFO] run-on histogram: \(runOns)
            [INFO] use-global comparison values: \(useGlobal); OR-flagged: \(orFlagged); \
            CIS1/CIS2 overrides: \(parameterNames)
            [INFO] distinct raw function indices: \(coverage.distinctIndices) \
            (min \(coverage.indexBounds.minimum), max \(coverage.indexBounds.maximum))
            [INFO] nonzero reference word while run-on is not Reference: \(nonReferenceGarbage)
            [INFO] records where CITC disagrees with the CTDA fields present: \
            \(countMismatches) \(ConditionStats.render(mismatchHistogram)); \
            unreadable records: \(unreadableRecords)
            [INFO] top condition-bearing record types: \(carriers)
            """
        }

        private static func render(_ histogram: [String: Int]) -> String {
            histogram.sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }.joined(separator: " ")
        }
    }

    private func sweep(file: ESMFile) -> ConditionStats {
        var stats = ConditionStats()
        ESMWalk.forEachRecord(in: file) { record in
            stats.records += 1
            guard let fields = try? record.fields() else {
                stats.unreadableRecords += 1
                return true
            }
            var list = ConditionList()
            var rawConditionFields = 0
            for field in fields {
                if field.type == "CTDA" {
                    rawConditionFields += 1
                }
                _ = try? list.decode(field: field)
            }
            accumulate(
                list: list,
                rawConditionFields: rawConditionFields,
                recordType: "\(record.type)",
                into: &stats
            )
            if !list.isEmpty {
                stats.recordsWithConditions += 1
                stats.recordTypeHistogram["\(record.type)", default: 0] += 1
            }
            return true
        }
        return stats
    }

    private func accumulate(
        list: ConditionList,
        rawConditionFields: Int,
        recordType: String,
        into stats: inout ConditionStats
    ) {
        stats.decoded += list.conditions.count
        stats.skipped += rawConditionFields - list.conditions.count
        // Observed in Skyrim.esm: every disagreement is a PACK, whose CITC
        // counts only the package's own condition run while further CTDA fields
        // belong to nested package-data blocks. CITC is therefore reported, not
        // trusted over the CTDA fields actually decoded.
        if let declared = list.declaredCount, declared != rawConditionFields {
            stats.countMismatches += 1
            stats.mismatchHistogram[recordType, default: 0] += 1
        }
        for condition in list.conditions {
            stats.operatorHistogram["\(condition.comparison)", default: 0] += 1
            stats.runOnHistogram["\(condition.runOn)", default: 0] += 1
            stats.coverage.record(condition)
            if case .global = condition.comparisonValue {
                stats.useGlobal += 1
            }
            if condition.flags.contains(.or) {
                stats.orFlagged += 1
            }
            if condition.parameter1Name != nil || condition.parameter2Name != nil {
                stats.parameterNames += 1
            }
            if condition.runOn != .reference, !condition.reference.isNull {
                stats.nonReferenceGarbage += 1
            }
        }
    }

    /// logs/condition-sweep.log (gitignored) next to the other real-data sidecars.
    private var logURL: URL {
        logsDirectory.appending(path: "condition-sweep.log")
    }

    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // openskyTests/
            .deletingLastPathComponent() // repo root
            .appending(path: "logs")
    }
}
