// Env-gated issue #474 coverage sweep over the user's active load order: what
// the magic condition functions add to the registry's reach.
//
// The aggregate counts are evidence only; no game bytes leave the run
// (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct ConditionMagicRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// The eight raw indices item 19.11 registers.
    private static let magicIndices: Set<UInt16> = [214, 223, 264, 570, 571, 572, 632, 699]

    /// Indices the progression items added afterwards: `HasPerk` (issue #497,
    /// item 20.4), and `GetLevel` and `GetBaseActorValue` (issue #499, item
    /// 20.6). Subtracted out for the reason `ConditionDataRealDataTests`
    /// subtracts the magic ones — this test pins the M19 step, not the registry
    /// as it happens to stand today.
    private static let laterIndices: Set<UInt16> = [80, 277, 448]

    /// Magic-adjacent indices the sweep measured and this milestone leaves
    /// tallied, so the tail is recorded rather than implied. See
    /// docs/formats/conditions.md for why each is deferred.
    private static let deferredIndices: [UInt16] = [
        101, 552, 595, 596, 597, 627, 664, 681, 693, 696, 706, 713, 724
    ]

    @Test(.enabled(if: Self.dataRoot != nil))
    func pinsMagicConditionCoverageImprovement() throws {
        let root = try #require(Self.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let coverage = Self.sweep(plugins: plugins)
        let registry = ConditionFunctionRegistry.standard
        let later = Self.laterIndices.reduce(0) { $0 + coverage.conditions(of: $1) }
        let after = coverage.implementedCount(in: registry) - later
        let added = Self.magicIndices.reduce(0) { $0 + coverage.conditions(of: $1) }
        let before = after - added

        #expect(coverage.total == 118_494)
        #expect(before == 76579)
        #expect(added == 618)
        #expect(after == 77197)
        // Every index registered is one vanilla data actually uses, which is
        // the measurement that chose them.
        for index in Self.magicIndices.sorted() {
            #expect(coverage.conditions(of: index) > 0)
        }
        print(
            "[INFO] magic condition coverage \(before)/\(coverage.total) -> "
                + "\(after)/\(coverage.total)"
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

    private static func sweep(
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
