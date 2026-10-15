// GetLocked, GetOpenState, IsUnlockedDoor, DoesNotExist, and GetInContainer read
// `ReferenceConditionFacts`; a reference with no facts fails with a reason.

import Foundation
@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
@testable import OpenSkyWorld
import Testing

struct ConditionReferenceStateFunctionTests {
    private static let subject = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.subjectFormID)

    private static func outcome(
        _ function: UInt16, equals value: Float, facts: ReferenceConditionFacts?,
        parameter1: UInt32 = 0
    ) throws -> ConditionOutcome {
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.referenceFacts = ReferenceConditionResolution(
            facts: facts.map { [subject: $0] } ?? [:]
        )
        var evaluator = ConditionEvaluator(context: context)
        return try evaluator.evaluate(ConditionEvaluatorFixture.comparing(
            functionIndex: function, 0, value, parameter1: parameter1
        ))
    }

    private static let lockedDoor = ReferenceConditionFacts(
        lock: ReferenceLockState(isLocked: true, level: 25, key: nil), isDoor: true
    )

    @Test func aLockedDoorIsLockedAndNotAnUnlockedDoor() throws {
        #expect(try Self.outcome(5, equals: 1, facts: Self.lockedDoor) == .true)
        #expect(try Self.outcome(718, equals: 0, facts: Self.lockedDoor) == .true)
        let open = ReferenceConditionFacts(isOpen: true, isDoor: true)
        #expect(try Self.outcome(718, equals: 1, facts: open) == .true)
        #expect(try Self.outcome(5, equals: 0, facts: open) == .true)
    }

    @Test func openStateUsesTheNativeCodes() throws {
        #expect(try Self
            .outcome(157, equals: 1, facts: ReferenceConditionFacts(isOpen: true)) == .true)
        #expect(try Self.outcome(157, equals: 3, facts: ReferenceConditionFacts()) == .true)
    }

    @Test func aDeletedReferenceDoesNotExist() throws {
        #expect(try Self
            .outcome(726, equals: 1, facts: ReferenceConditionFacts(isDeleted: true)) == .true)
        #expect(try Self.outcome(726, equals: 0, facts: ReferenceConditionFacts()) == .true)
    }

    @Test func noPlacedReferenceIsInsideAContainer() throws {
        let container = ConditionEvaluatorFixture.targetFormID
        #expect(try Self.outcome(
            624, equals: 0, facts: ReferenceConditionFacts(), parameter1: container
        ) == .true)
    }

    @Test func aReferenceWithoutFactsFailsWithAReason() throws {
        #expect(try Self.outcome(5, equals: 0, facts: nil)
            .failures == [.unavailableData(.reference)])
    }
}
