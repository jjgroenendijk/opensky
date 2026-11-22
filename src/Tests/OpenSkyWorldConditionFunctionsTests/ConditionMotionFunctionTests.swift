// The motion condition functions read `ReferenceMotionFacts`: position, heading,
// velocity, and the path. A reference with no motion fails with a reason.

import Foundation
@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
@testable import OpenSkyWorldConditionFunctions
import OpenSkyWorldInterface
import Testing

struct ConditionMotionFunctionTests {
    /// The core functions and this family's, the set these tests run on.
    static let registry: ConditionFunctionRegistry = {
        var registry = ConditionFunctionRegistry()
        ConditionFunctions.installCore(into: &registry)
        ConditionFunctionsMotion.installMotion(&registry)
        return registry
    }()

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
        var evaluator = ConditionEvaluator(context: context.using(Self.registry))
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

    /// A null parameter 1 names the other reference of the run-on.
    @Test func aNullParameterMeasuresToTheOtherReference() throws {
        #expect(try Self.outcome(720, equals: 64) == .true)
        let near = Float(120).bitPattern
        #expect(try Self.outcome(639, equals: 1, parameter2: near) == .true)

        var context = try ConditionEvaluatorFixture.populatedContext()
        context.motion = MotionConditionResolution(facts: [
            Self.subject: Self.walker,
            Self.target: ReferenceMotionFacts(position: SIMD3(100, 0, 74))
        ])
        func height(runOn: UInt32, flags: UInt8 = 0) throws -> Condition {
            try ConditionEvaluatorFixture.condition(
                flags: flags, comparisonValue: Float(-64).bitPattern, functionIndex: 720,
                runOn: runOn
            )
        }
        var evaluator = ConditionEvaluator(context: context.using(Self.registry))
        // Run on the target, the other reference is the subject.
        #expect(try evaluator.evaluate(height(runOn: 1)) == .true)
        // The swap flag swaps both, so the subject run-on reads the target's side.
        #expect(try evaluator.evaluate(height(runOn: 0, flags: 0x10)) == .true)
        // With the alias flag the rule is off.
        #expect(try evaluator.evaluate(height(runOn: 1, flags: 0x02)) != .true)

        context.target = nil
        var alone = ConditionEvaluator(context: context.using(Self.registry))
        let zero = try ConditionEvaluatorFixture.condition(functionIndex: 720)
        #expect(alone.evaluate(zero) == .true)
        let distance = try ConditionEvaluatorFixture.condition(functionIndex: 639)
        #expect(alone.evaluate(distance).failures == [.unresolvedParameter(639)])
    }

    /// The relative angle compares the two rotations, not the two places.
    @Test func theRelativeAngleIsTheDifferenceOfTheRotations() throws {
        let facing = ReferenceMotionFacts(
            position: SIMD3(100, 0, 74), rotation: SIMD3(0, 0, .pi)
        )
        #expect(try Self.outcome(584, equals: 180, other: facing, parameter2: Self.axisZ) == .true)
        var turned = Self.walker
        turned.rotation.z = .pi / 2
        let same = ReferenceMotionFacts(position: .zero, rotation: SIMD3(0, 0, .pi))
        #expect(try Self.outcome(
            584, equals: 270, subject: turned, other: same, parameter2: Self.axisZ
        ) == .true)
        #expect(try Self.outcome(584, equals: 0, other: facing, parameter2: 7) == .true)
    }

    /// A reference the table lacks is read through the lookup when a condition asks.
    @MainActor
    @Test func theLookupAnswersForAReferenceTheTableLacks() throws {
        var context = try ConditionEvaluatorFixture.populatedContext()
        let walker = Self.walker
        context.motion = MotionConditionResolution(facts: [:]) { key in
            key == Self.subject ? walker : nil
        }
        var evaluator = ConditionEvaluator(context: context.using(Self.registry))
        let position = try ConditionEvaluatorFixture.condition(
            comparisonValue: Float(10).bitPattern, functionIndex: 6, parameter1: Self.axisZ
        )
        #expect(evaluator.evaluate(position) == .true)
    }

    @Test func noMotionFailsWithAReason() throws {
        #expect(try Self.outcome(25, equals: 0, subject: nil)
            .failures == [.unavailableData(.motion)])
    }
}
