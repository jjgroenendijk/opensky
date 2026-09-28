// The text the CTDA coverage sweep leaves behind in gitignored `logs/`
// (issue #251), kept apart from the tally itself so neither file crowds the
// length caps.
//
// Every number here is an aggregate over the user's own install; the report
// names function indices and counts, never records.

import Foundation
@testable import opensky

extension ConditionCoverage {
    /// How many unimplemented functions the ranked table shows.
    static let rankedUnimplementedLimit = 20

    /// Full coverage report: the headline ratio, what the registry already
    /// answers, what it misses most, and shape evidence for the indices under
    /// dispute.
    func report(
        registry: ConditionFunctionRegistry = .standard,
        probing probeIndices: [UInt16] = []
    ) -> String {
        ([headline(registry: registry)]
            + implementedLines(registry: registry)
            + unimplementedLines(registry: registry)
            + probeLines(probeIndices, registry: registry))
            .joined(separator: "\n")
    }

    private func headline(registry: ConditionFunctionRegistry) -> String {
        let implemented = implementedCount(in: registry)
        let percent = String(format: "%.2f", coverageFraction(in: registry) * 100)
        let bounds = indexBounds
        return """
        [INFO] condition-function coverage: \(implemented)/\(total) conditions \
        evaluable (\(percent)%), registry holds \(registry.count) of \
        \(distinctIndices) distinct raw indices \
        (min \(bounds.minimum), max \(bounds.maximum))
        """
    }

    private func implementedLines(registry: ConditionFunctionRegistry) -> [String] {
        ["[INFO] per implemented function (raw / Creation Kit / conditions):"]
            + implementedCounts(in: registry).map { entry in
                "  \(entry.function.name): raw \(entry.function.index), "
                    + "CK \(entry.function.creationKitIndex), \(entry.conditions)"
            }
    }

    private func unimplementedLines(registry: ConditionFunctionRegistry) -> [String] {
        let ranked = rankedUnimplemented(in: registry)
        let missed = ranked.reduce(0) { $0 + $1.conditions }
        let header = """
        [INFO] top \(Self.rankedUnimplementedLimit) unimplemented functions of \
        \(ranked.count), carrying \(missed) conditions \
        (raw / Creation Kit / conditions):
        """
        return [header] + ranked.prefix(Self.rankedUnimplementedLimit).map { entry in
            "  raw \(entry.index), CK "
                + "\(Int(entry.index) + ConditionFunctionRegistry.creationKitOffset), "
                + "\(entry.conditions)"
        }
    }

    /// Shape evidence for specific indices, which is how a disputed index is
    /// settled: parameter words that are always zero mean the function declares
    /// no parameters, and comparisons spread over 0-100 mean it returns a
    /// percentage.
    private func probeLines(
        _ probeIndices: [UInt16],
        registry: ConditionFunctionRegistry
    ) -> [String] {
        guard !probeIndices.isEmpty else { return [] }
        return ["[INFO] signature probe (raw / Creation Kit):"]
            + probeIndices.map { index in
                let creationKit = Int(index) + ConditionFunctionRegistry.creationKitOffset
                let registered = registry[index].map { " registered as \($0.name)" } ?? ""
                guard let shape = shape(of: index) else {
                    return "  raw \(index), CK \(creationKit): absent\(registered)"
                }
                return "  raw \(index), CK \(creationKit): \(shape.signature)"
                    + "\(registered)"
            }
    }
}
