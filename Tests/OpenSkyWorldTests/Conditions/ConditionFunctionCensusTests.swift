// ConditionFunctionCensus: counts CTDA function indices and ranks the ones a
// registry cannot answer, from real 32-byte CTDA fields.

import Foundation
@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
import Testing

struct ConditionFunctionCensusTests {
    @Test func ranksUnregisteredFunctionsByUse() throws {
        var census = ConditionFunctionCensus()
        census.record(fields: [
            ConditionEvaluatorFixture.field(functionIndex: 7),
            ConditionEvaluatorFixture.field(functionIndex: 9),
            ConditionEvaluatorFixture.field(functionIndex: 9),
            ESMField(type: "EDID", data: Data("x\0".utf8))
        ])
        try census.record(ConditionEvaluatorFixture.condition(functionIndex: 3))

        var registry = ConditionFunctionRegistry()
        registry.register(ConditionFunction(index: 3, name: "Known") { _ in .success(1) })

        #expect(census.total == 4)
        let missing = census.missing(in: registry)
        #expect(missing.map(\.index) == [9, 7])
        #expect(missing.map(\.count) == [2, 1])
        #expect(census.missing(in: .empty).count == 3)
    }

    @Test func tiesRankByIndex() {
        var census = ConditionFunctionCensus()
        census.record(fields: [
            ConditionEvaluatorFixture.field(functionIndex: 20),
            ConditionEvaluatorFixture.field(functionIndex: 10)
        ])
        #expect(census.missing(in: .empty).map(\.index) == [10, 20])
    }

    /// A registered name that differs from the Creation Kit table means a wrong index.
    @Test func everyRegisteredFunctionHasItsCreationKitName() {
        let mismatches = ConditionFunctionRegistry.standard.sortedFunctions()
            .filter { ConditionFunctionNames.name(for: $0.index) != $0.name }
            .map {
                "\($0.index) \($0.name) vs \(ConditionFunctionNames.name(for: $0.index) ?? "none")"
            }
        #expect(mismatches.isEmpty, "\(mismatches)")
    }
}
