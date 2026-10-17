// Condition coverage sweep over the real load order: what the magic condition
// functions add to the registry's reach. Only aggregate counts leave the run.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import Testing

struct ConditionMagicRealDataTests {
    /// The eight raw indices item 19.11 registers.
    private static let magicIndices: Set<UInt16> = [214, 223, 264, 570, 571, 572, 632, 699]

    /// Magic-adjacent indices the sweep measured and this milestone leaves
    /// tallied, so the tail is recorded rather than implied. See
    /// docs/engine/condition-functions.md for why each is deferred.
    private static let deferredIndices: [UInt16] = [
        101, 552, 595, 596, 597, 627, 664, 681, 693, 696, 706, 713, 724
    ]

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func pinsMagicConditionCoverageImprovement() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let coverage = ConditionCoverage.sweep(plugins: plugins)
        let registry = ConditionFunctionRegistry.standard
        let implemented = coverage.implementedCount(in: registry)
        let added = Self.magicIndices.reduce(0) { $0 + coverage.conditions(of: $1) }

        #expect(coverage.total == 118_494)
        // Only this step's own indices, so a newly registered function does not
        // move the pin.
        #expect(added == 618)
        #expect(Self.magicIndices.allSatisfy { registry[$0] != nil })
        // Every index registered is one vanilla data actually uses, which is
        // the measurement that chose them.
        for index in Self.magicIndices.sorted() {
            #expect(coverage.conditions(of: index) > 0)
        }
        print(
            "[INFO] magic conditions answered \(added); registry answers "
                + "\(implemented)/\(coverage.total)"
        )
        for index in Self.magicIndices.sorted() {
            print(
                "[INFO] answered \(registry.name(for: index)): "
                    + "\(coverage.conditions(of: index))"
            )
        }
        for index in Self.deferredIndices {
            print("[INFO] still tallied raw \(index): \(coverage.conditions(of: index))")
        }
    }
}
