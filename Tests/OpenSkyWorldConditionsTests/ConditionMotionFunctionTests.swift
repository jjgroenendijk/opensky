// The motion condition functions read `ReferenceMotionFacts`: position, heading,
// velocity, and the path. A reference with no motion fails with a reason.

import Foundation
@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
@testable import OpenSkyWorldConditions
import Testing

struct ConditionMotionFunctionTests {
    private static let subject = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.subjectFormID)
    private static let target = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.targetFormID)
    private static let axisX: UInt32 = 88
    private static let axisZ: UInt32 = 90

    /// Facing north (+Y), walking forward at 100 units a second toward a waypoint east.
    private static let walker = ReferenceMotionFacts(
        position: SIMD3(0, 0, 10),
        velocity: SIMD3(0, 100, 0),
        pathTarget: SIMD3(50, 0, 10),
        pathTargetSpeed: 150,
        pathTurnSpeed: .pi
    )

    private static func outcome(
        _ function: UInt16, equals value: Float, comparison: UInt8 = 0,
        subject facts: ReferenceMotionFacts? = walker,
        other: ReferenceMotionFacts = ReferenceMotionFacts(position: SIMD3(100, 0, 74)),
        parameter1: UInt32 = 0, parameter2: UInt32 = 0
    ) throws -> ConditionOutcome {
        var context = try ConditionEvaluatorFixture.populatedContext()
        var table = [target: other]
        table[subject] = facts
        context.motion = MotionConditionResolution(facts: table)
        var evaluator = ConditionEvaluator(context: context)
        return try evaluator.evaluate(ConditionEvaluatorFixture.condition(
            operatorBits: comparison, comparisonValue: value.bitPattern, functionIndex: function,
            parameter1: parameter1, parameter2: parameter2
        ))
    }

    @Test func positionAndVelocityReadOneAxis() throws {
        #expect(try Self.outcome(6, equals: 10, parameter1: Self.axisZ) == .true)
        #expect(try Self.outcome(446, equals: 0, parameter1: Self.axisX) == .true)
        #expect(try Self.outcome(6, equals: 0, parameter1: 7).failures == [.unresolvedParameter(6)])
    }

    @Test func forwardMotionIsMovingForward() throws {
        #expect(try Self.outcome(25, equals: 1) == .true)
        #expect(try Self.outcome(589, equals: 1) == .true)
        #expect(try Self.outcome(623, equals: 100) == .true)
        let standing = ReferenceMotionFacts(position: .zero)
        #expect(try Self.outcome(25, equals: 0, subject: standing) == .true)
        #expect(try Self.outcome(704, equals: 0, subject: standing) == .true)
    }

    @Test func pathReadsTheNextWaypoint() throws {
        #expect(try Self.outcome(704, equals: 1) == .true)
        #expect(try Self.outcome(621, equals: 150) == .true)
        #expect(try Self.outcome(620, equals: 90, parameter1: Self.axisZ) == .true)
        #expect(try Self.outcome(684, equals: 180, parameter1: Self.axisZ) == .true)
    }

    @Test func pairFunctionsMeasureToTheParameter() throws {
        let target = ConditionEvaluatorFixture.targetFormID
        #expect(try Self.outcome(99, equals: 90, parameter1: target) == .true)
        #expect(try Self.outcome(720, equals: 64, parameter1: target) == .true)
        let near = Float(120).bitPattern
        #expect(try Self.outcome(639, equals: 1, parameter1: target, parameter2: near) == .true)
        let far = Float(50).bitPattern
        #expect(try Self.outcome(639, equals: 0, parameter1: target, parameter2: far) == .true)
    }

    @Test func noMotionFailsWithAReason() throws {
        #expect(try Self.outcome(25, equals: 0, subject: nil)
            .failures == [.unavailableData(.motion)])
    }
}
