// GetIsCurrentPackage and the package-data functions read `ActorPackageFacts`; an
// actor that runs no package reads 0, and an unwired context fails with a reason.

import Foundation
@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
import Testing

struct ConditionPackageFunctionTests {
    private static let subject = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.subjectFormID)
    private static let package = FormID(0x0001_2345)

    private static func outcome(
        _ function: UInt16, equals value: Float, parameter1: UInt32 = 0,
        facts: [ReferenceKey: ActorPackageFacts]?
    ) throws -> ConditionOutcome {
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.packages = PackageConditionResolution(facts: facts)
        var evaluator = ConditionEvaluator(context: context)
        return try evaluator.evaluate(ConditionEvaluatorFixture.comparing(
            functionIndex: function, 0, value, parameter1: parameter1
        ))
    }

    private static let running: [ReferenceKey: ActorPackageFacts] = [
        subject: ActorPackageFacts(
            package: package,
            procedure: .sandbox,
            dataInputs: [
                0: .location(Package.Location(rawKind: 0, value: 0x1234, radius: 300)),
                1: .integer(7),
                2: .float(2.5),
                3: .topic(FormID(0))
            ],
            withinLocations: [0]
        )
    ]

    @Test func theRunningPackageIsTheCurrentOne() throws {
        #expect(try Self
            .outcome(161, equals: 1, parameter1: 0x0001_2345, facts: Self.running) == .true)
        #expect(try Self
            .outcome(161, equals: 0, parameter1: 0x0001_0999, facts: Self.running) == .true)
        #expect(try Self.outcome(161, equals: 0, parameter1: 0x0001_2345, facts: [:]) == .true)
    }

    @Test func numericDataReadsTheInput() throws {
        #expect(try Self.outcome(612, equals: 7, parameter1: 1, facts: Self.running) == .true)
        #expect(try Self.outcome(612, equals: 2.5, parameter1: 2, facts: Self.running) == .true)
        #expect(try Self.outcome(612, equals: 0, parameter1: 0, facts: Self.running) == .true)
    }

    @Test func anEmptyTopicIsNullDataAndAPlaceIsNot() throws {
        #expect(try Self.outcome(611, equals: 1, parameter1: 3, facts: Self.running) == .true)
        #expect(try Self.outcome(611, equals: 0, parameter1: 0, facts: Self.running) == .true)
        #expect(try Self.outcome(611, equals: 1, parameter1: 9, facts: Self.running) == .true)
    }

    @Test func withinLocationReadsTheActorsPlace() throws {
        #expect(try Self.outcome(325, equals: 1, parameter1: 0, facts: Self.running) == .true)
        #expect(try Self.outcome(325, equals: 0, parameter1: 1, facts: Self.running) == .true)
    }

    @Test func packageFlagsAnswerServicesSleepAndInteractions() throws {
        let vendor: [ReferenceKey: ActorPackageFacts] = [
            Self.subject: ActorPackageFacts(
                package: Self.package, procedure: .sleep,
                flags: .offersServices, interruptFlags: 0x200
            )
        ]
        #expect(try Self.outcome(49, equals: 3, facts: vendor) == .true)
        #expect(try Self.outcome(255, equals: 1, facts: vendor) == .true)
        #expect(try Self.outcome(503, equals: 1, facts: vendor) == .true)
        #expect(try Self.outcome(49, equals: 0, facts: Self.running) == .true)
        #expect(try Self.outcome(255, equals: 0, facts: Self.running) == .true)
        #expect(try Self.outcome(503, equals: 0, facts: [:]) == .true)
    }

    @Test func anUnwiredContextFailsWithAReason() throws {
        #expect(try Self.outcome(161, equals: 0, facts: nil)
            .failures == [.unavailableData(.package)])
    }
}
