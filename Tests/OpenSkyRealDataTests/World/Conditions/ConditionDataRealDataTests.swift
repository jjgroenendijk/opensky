// Condition coverage sweep over the real load order. Only aggregate counts
// leave the run.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import Testing

struct ConditionDataRealDataTests {
    private static let m18Indices: Set<UInt16> = [
        180, 181, 359, 360, 372, 444, 560, 562, 565, 567, 603, 604, 605, 610
    ]

    /// Indices added after the M18 functions: magic, `HasPerk`, `GetLevel`,
    /// `GetBaseActorValue`, faction, crime-gold, and `GetItemCount`. They are subtracted, so the
    /// two pinned numbers stay the registry before and after M18.
    private static let laterIndices: Set<UInt16> = [
        80, 214, 223, 264, 277, 448, 570, 571, 572, 632, 699,
        60, 71, 73, 403, 449, 719, 375, 376, 459, 47
    ]

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func pinsActiveLoadOrderCoverageImprovement() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let coverage = ConditionCoverage.sweep(plugins: plugins)
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
}
