// The mount functions read who rides what; the flight functions answer the grounded
// value, because no actor flies yet.

import Foundation
@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
@testable import OpenSkyWorldConditions
import Testing

struct ConditionMountFunctionTests {
    private static let subject = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.subjectFormID)
    private static let target = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.targetFormID)

    private static func outcome(
        _ function: UInt16, equals value: Float, mounts: MountConditionResolution
    ) throws -> ConditionOutcome {
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.mounts = mounts
        var evaluator = ConditionEvaluator(context: context)
        return try evaluator.evaluate(ConditionEvaluatorFixture.comparing(
            functionIndex: function, 0, value
        ))
    }

    @Test func aRiderAndItsMountAnswer() throws {
        let riding = MountConditionResolution(
            mounts: [Self.subject: Self.target], playersLastMount: Self.subject
        )
        #expect(try Self.outcome(327, equals: 1, mounts: riding) == .true)
        #expect(try Self.outcome(714, equals: 0, mounts: riding) == .true)
        #expect(try Self.outcome(339, equals: 1, mounts: riding) == .true)
        let ridden = MountConditionResolution(
            mounts: [Self.target: Self.subject], playersLastMount: nil
        )
        #expect(try Self.outcome(714, equals: 1, mounts: ridden) == .true)
        #expect(try Self.outcome(327, equals: 0, mounts: ridden) == .true)
    }

    @Test func aRiderOnADragonIsOnAFlyingMount() throws {
        let dragon = MountConditionResolution(
            mounts: [Self.subject: Self.target], playersLastMount: nil,
            flyingMounts: [Self.target]
        )
        #expect(try Self.outcome(730, equals: 1, mounts: dragon) == .true)
        let horse = MountConditionResolution(
            mounts: [Self.subject: Self.target], playersLastMount: nil
        )
        #expect(try Self.outcome(730, equals: 0, mounts: horse) == .true)
    }

    @Test func flightReadsTheGroundedValue() throws {
        let grounded = MountConditionResolution(mounts: [:], playersLastMount: nil)
        for function: UInt16 in [282, 633, 646, 647, 730, 731, 732, 733] {
            #expect(try Self.outcome(function, equals: 0, mounts: grounded) == .true)
        }
        #expect(try Self.outcome(327, equals: 0, mounts: .empty)
            .failures == [.unavailableData(.mount)])
    }
}
