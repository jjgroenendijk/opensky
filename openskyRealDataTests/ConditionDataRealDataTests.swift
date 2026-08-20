// Env-gated issue #455 coverage sweep over the user's active load order. The
// aggregate counts are evidence only; no game bytes leave the run.

import Foundation
@testable import opensky
import Testing

struct ConditionDataRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static let m18Indices: Set<UInt16> = [
        180, 181, 359, 360, 372, 444, 560, 562, 565, 567, 603, 604, 605, 610
    ]

    /// Every index a later item added. Subtracted out so the two numbers this
    /// test pins keep meaning what they meant when #455 measured them: the
    /// registry before and after the M18 functions, not the registry as it
    /// happens to stand today. `ConditionMagicRealDataTests` pins the M19 step
    /// from the other side, and excludes the M20 ones for the same reason.
    ///
    /// The eight magic indices are item 19.11's (issue #474); `HasPerk` is item
    /// 20.4's (issue #497); `GetLevel` and `GetBaseActorValue` are item 20.6's
    /// (issue #499).
    private static let laterIndices: Set<UInt16> = [
        80, 214, 223, 264, 277, 448, 570, 571, 572, 632, 699
    ]

    @Test(.enabled(if: Self.dataRoot != nil))
    func pinsActiveLoadOrderCoverageImprovement() throws {
        let root = try #require(Self.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let coverage = sweep(plugins: plugins)
        let registry = ConditionFunctionRegistry.standard
        let later = Self.laterIndices.reduce(0) { $0 + coverage.conditions(of: $1) }
        let afterM18 = coverage.implementedCount(in: registry) - later
        let added = Self.m18Indices.reduce(0) { $0 + coverage.conditions(of: $1) }
        let beforeM18 = afterM18 - added

        #expect(plugins.map(\.name) == [
            "Skyrim.esm", "Update.esm", "Dawnguard.esm", "HearthFires.esm",
            "Dragonborn.esm", "ccBGSSSE001-Fish.esm", "ccQDRSSE001-SurvivalMode.esl",
            "ccBGSSSE037-Curios.esl", "ccBGSSSE025-AdvDSGS.esm", "_ResourcePack.esl"
        ])
        #expect(coverage.total == 118_494)
        #expect(beforeM18 == 69225)
        #expect(added == 7354)
        #expect(afterM18 == 76579)
        #expect(afterM18 > beforeM18)
        print(
            "[INFO] M18 condition coverage \(beforeM18)/\(coverage.total) -> "
                + "\(afterM18)/\(coverage.total)"
        )
        print(coverage.report())
    }

    private func sweep(
        plugins: [(name: String, file: ESMFile)]
    ) -> ConditionCoverage {
        var coverage = ConditionCoverage()
        for plugin in plugins {
            ESMWalk.forEachRecord(in: plugin.file) { record in
                guard let fields = try? record.fields() else { return true }
                var list = ConditionList()
                for field in fields {
                    _ = try? list.decode(field: field)
                }
                for condition in list.conditions {
                    coverage.record(condition)
                }
                return true
            }
        }
        return coverage
    }
}
