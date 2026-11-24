// GetOffersServicesNow asks the vendor rules, not the running package; an unwired
// context fails with a reason.

import Foundation
@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyWorldConditions
import Testing

@MainActor
struct ConditionServicesFunctionTests {
    private static let subject = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.subjectFormID)

    private static func outcome(
        equals value: Float, services: ServicesConditionResolution
    ) throws -> ConditionOutcome {
        var context = try ConditionEvaluatorFixture.populatedContext()
        context[resolution: ServicesConditionResolution.self] = services
        var evaluator = ConditionEvaluator(context: context.using(.standard))
        return try evaluator.evaluate(ConditionEvaluatorFixture.comparing(
            functionIndex: 255, 0, value
        ))
    }

    @Test func aVendorOffersServicesWhenTheRulesSaySo() throws {
        let open = ServicesConditionResolution { $0 == Self.subject }
        #expect(try Self.outcome(equals: 1, services: open) == .true)
        let closed = ServicesConditionResolution { _ in false }
        #expect(try Self.outcome(equals: 0, services: closed) == .true)
    }

    @Test func anUnwiredContextFailsWithAReason() throws {
        #expect(try Self.outcome(equals: 0, services: .empty)
            .failures == [.unavailableData(.inventory)])
    }
}
