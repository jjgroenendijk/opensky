// The three perception condition functions (issue #202, roadmap item 16.6),
// driven through the real evaluator against a synthetic pair.
//
// Function indices here are the raw on-disk numbers (Creation Kit number minus
// 4096) — see the ConditionFunctionsDetection.swift header for the sources.
//
// Fixtures are synthetic — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import opensky
import simd
import Testing

struct ConditionDetectionFunctionTests {
    private static let getDistance: UInt16 = 1
    private static let getLineOfSight: UInt16 = 27
    private static let getDetected: UInt16 = 45

    private static let observerKey = ConditionEvaluatorFixture.key(
        ConditionEvaluatorFixture.subjectFormID
    )
    private static let targetKey = ConditionEvaluatorFixture.key(
        ConditionEvaluatorFixture.targetFormID
    )

    /// A pair the observer has detected through a clear sight line, standing
    /// 300 units apart along +X.
    private static func detectingContext(
        state: DetectionState = .detected,
        hasLineOfSight: Bool = true,
        placesTarget: Bool = true
    ) throws -> ConditionContext {
        var context = try ConditionEvaluatorFixture.populatedContext()
        var pair = DetectionPairState()
        pair.state = state
        pair.level = state == .detected ? 100 : 40
        pair.hasLineOfSight = hasLineOfSight
        var positions: [ReferenceKey: SIMD3<Float>] = [observerKey: SIMD3(0, 0, 0)]
        if placesTarget {
            positions[targetKey] = SIMD3(300, 0, 0)
        }
        context.detection = DetectionResolution(
            pairs: [DetectionPairKey(observer: observerKey, target: targetKey): pair],
            positions: positions
        )
        return context
    }

    /// `functionIndex <comparison> value`, with parameter 1 naming the target
    /// placement and the run-on naming the observer.
    private static func evaluate(
        _ functionIndex: UInt16,
        _ comparison: UInt8,
        _ value: Float,
        parameter1: UInt32 = ConditionEvaluatorFixture.targetFormID,
        runOn: UInt32 = 0,
        context: ConditionContext
    ) throws -> (outcome: ConditionOutcome, tally: ConditionTally) {
        var evaluator = ConditionEvaluator(context: context)
        let outcome = try evaluator.evaluate(ConditionEvaluatorFixture.comparing(
            functionIndex: functionIndex,
            comparison,
            value,
            runOn: runOn,
            parameter1: parameter1
        ))
        return (outcome, evaluator.tally)
    }

    // MARK: - Registration

    @Test func theThreeFunctionsAreRegisteredAtTheirXEditIndices() {
        let registry = ConditionFunctionRegistry.standard
        #expect(registry[Self.getDistance]?.name == "GetDistance")
        #expect(registry[Self.getLineOfSight]?.name == "GetLineOfSight")
        #expect(registry[Self.getDetected]?.name == "GetDetected")
        // The Creation Kit spells each one 4096 higher.
        #expect(registry[Self.getDistance]?.creationKitIndex == 4097)
        #expect(registry[Self.getLineOfSight]?.creationKitIndex == 4123)
        #expect(registry[Self.getDetected]?.creationKitIndex == 4141)
        // All three take a reference in parameter 1 and nothing in parameter 2.
        #expect(registry[Self.getDetected]?.parameter1 == .formID)
        #expect(registry[Self.getDetected]?.parameter2 == .unused)
    }

    // MARK: - Answers

    @Test func getDistanceMeasuresBetweenTheRunOnAndTheParameter() throws {
        let context = try Self.detectingContext()
        #expect(try Self.evaluate(Self.getDistance, 0, 300, context: context).outcome == .true)
        // Symmetric: asking from the other side gives the same number.
        #expect(try Self.evaluate(
            Self.getDistance, 0, 300,
            parameter1: ConditionEvaluatorFixture.subjectFormID, runOn: 1, context: context
        ).outcome == .true)
        // Greater-than against a shorter distance, so the comparison itself is
        // exercised rather than only equality.
        #expect(try Self.evaluate(Self.getDistance, 2, 100, context: context).outcome == .true)
    }

    @Test func getDetectedAndGetLineOfSightReadThePair() throws {
        let detected = try Self.detectingContext()
        #expect(try Self.evaluate(Self.getDetected, 0, 1, context: detected).outcome == .true)
        #expect(try Self.evaluate(
            Self.getLineOfSight, 0, 1, context: detected
        ).outcome == .true)

        // A suspicious observer has not detected anything: it has somewhere to
        // go and look. The sight line is a separate fact and stays true.
        let suspicious = try Self.detectingContext(state: .suspicious)
        #expect(try Self.evaluate(Self.getDetected, 0, 0, context: suspicious).outcome == .true)
        #expect(try Self.evaluate(
            Self.getLineOfSight, 0, 1, context: suspicious
        ).outcome == .true)

        // Blocked: no sight line, and detection through the wall alone.
        let blocked = try Self.detectingContext(hasLineOfSight: false)
        #expect(try Self.evaluate(
            Self.getLineOfSight, 0, 0, context: blocked
        ).outcome == .true)
    }

    @Test func detectionIsAskedInOneDirectionOnly() throws {
        // Run-on 1 makes the *target* the observer, and the pass tracks no such
        // pair. That is a reason-tagged false, not a "not detected".
        let context = try Self.detectingContext()
        let result = try Self.evaluate(
            Self.getDetected, 0, 0,
            parameter1: ConditionEvaluatorFixture.subjectFormID, runOn: 1, context: context
        )
        #expect(!result.outcome.isTrue)
        #expect(result.outcome.failures == [.unavailableDetection])
        #expect(result.tally.unavailableDetection == 1)
        #expect(!result.tally.isClean)
    }

    // MARK: - Misses

    @Test func anEmptySeamIsAReasonTaggedFalseRatherThanAnUndetectedActor() throws {
        let context = try ConditionEvaluatorFixture.populatedContext()
        #expect(context.detection.isEmpty)
        for index in [Self.getDetected, Self.getLineOfSight, Self.getDistance] {
            let result = try Self.evaluate(index, 0, 0, context: context)
            #expect(!result.outcome.isTrue)
            #expect(result.outcome.failures == [.unavailableDetection])
        }
    }

    @Test func aParameterNamingNoReferenceIsATalliedParameterMiss() throws {
        let context = try Self.detectingContext()
        let result = try Self.evaluate(
            Self.getDetected, 0, 1, parameter1: 0x00DE_AD00, context: context
        )
        #expect(!result.outcome.isTrue)
        #expect(result.outcome.failures == [.unresolvedParameter(Self.getDetected)])
        #expect(result.tally.unresolvedParameters == [Self.getDetected: 1])
    }

    @Test func anUnplacedReferenceMakesTheDistanceUnavailableRatherThanZero() throws {
        let context = try Self.detectingContext(placesTarget: false)
        let result = try Self.evaluate(Self.getDistance, 0, 0, context: context)
        #expect(!result.outcome.isTrue)
        #expect(result.outcome.failures == [.unavailableDetection])
        // The pair itself is still tracked, so the other two still answer.
        #expect(try Self.evaluate(Self.getDetected, 0, 1, context: context).outcome == .true)
    }
}
