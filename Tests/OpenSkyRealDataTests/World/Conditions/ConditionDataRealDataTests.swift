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

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func pinsActiveLoadOrderCoverageImprovement() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let coverage = ConditionCoverage.sweep(plugins: plugins)
        let registry = ConditionFunctionRegistry.standard
        let implemented = coverage.implementedCount(in: registry)
        let added = Self.m18Indices.reduce(0) { $0 + coverage.conditions(of: $1) }

        #expect(plugins.map(\.name) == [
            "Skyrim.esm", "Update.esm", "Dawnguard.esm", "HearthFires.esm",
            "Dragonborn.esm", "ccBGSSSE001-Fish.esm", "ccQDRSSE001-SurvivalMode.esl",
            "ccBGSSSE037-Curios.esl", "ccBGSSSE025-AdvDSGS.esm", "_ResourcePack.esl"
        ])
        #expect(coverage.total == 118_494)
        // Each step pins only its own indices, so a newly registered function
        // does not move this number.
        #expect(added == 7354)
        #expect(Self.m18Indices.allSatisfy { registry[$0] != nil })
        print(
            "[INFO] M18 conditions answered \(added); registry answers "
                + "\(implemented)/\(coverage.total)"
        )
        print(coverage.report())
    }
}
