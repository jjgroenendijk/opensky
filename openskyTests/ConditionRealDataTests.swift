// Env-gated CTDA sweep over the user's own Skyrim SE install (read-only
// external input, never committed — AGENTS.md Legal & IP): decodes every CTDA
// subrecord of every record in Skyrim.esm and asserts none of them throws.
// Groundwork for the condition-function coverage tally (issue #251), so it
// decodes fields directly rather than through per-record wiring. Skips
// automatically when OPENSKY_DATA_ROOT is unset/unresolvable (CI has no game
// data). Summary printed + written to logs/.
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

    @Test(.enabled(if: Self.dataRoot != nil))
    func sweepsEveryConditionInSkyrimESM() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))

        let stats = sweep(file: file)
        #expect(stats.decoded > 0, "no CTDA subrecords in Skyrim.esm")
        #expect(stats.skipped == 0, "wrong-size CTDA payloads in Skyrim.esm")
        #expect(stats.unreadableRecords == 0, "records whose fields failed to parse")

        let summary = stats.summary
        print(summary)
        try? summary.write(to: logURL, atomically: true, encoding: .utf8)
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
        var functionIndices = Set<UInt16>()
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
            [INFO] distinct raw function indices: \(functionIndices.count) \
            (min \(functionIndices.min() ?? 0), max \(functionIndices.max() ?? 0))
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
            stats.functionIndices.insert(condition.functionIndex)
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
