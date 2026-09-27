// Coverage for the per-condition report the World > Runtime State Conditions
// section shows (issue #166, roadmap item 10.2.4).
//
// The load-bearing claim is that the runner's verdict is the same answer
// `ConditionEvaluator.evaluate(_ conditions:)` gives, even though the runner
// reaches it by evaluating each condition on its own to collect the reasons.
// Several tests therefore assert the two side by side rather than against a
// hand-written expectation, so a change to the evaluator's OR grouping fails
// here instead of drifting silently.
//
// Every condition is a real 32-byte CTDA payload from `ConditionEvaluatorFixture`,
// synthetic and built in code; no game data is read.

@testable import opensky
import Testing

struct RuntimeStateConditionRunnerTests {
    /// Raw on-disk index of `GetGlobalValue` (Creation Kit 4170).
    private static let getGlobalValue: UInt16 = 74
    /// An index the registry deliberately does not implement.
    private static let unimplemented: UInt16 = 9999

    @Test
    func perConditionReasonsNameTheConditionThatFailed() throws {
        let conditions = try [
            ConditionEvaluatorFixture.comparing(
                functionIndex: Self.getGlobalValue, 0, 1,
                parameter1: ConditionEvaluatorFixture.flagFormID
            ),
            ConditionEvaluatorFixture.comparing(functionIndex: Self.unimplemented, 0, 1)
        ]
        var tally = ConditionTally()
        let report = try RuntimeStateConditionRunner.report(
            source: "MUSTest",
            conditions: conditions,
            context: ConditionEvaluatorFixture.populatedContext(),
            tally: &tally
        )

        #expect(report.source == "MUSTest")
        #expect(!report.isSatisfied)
        #expect(report.message == nil)
        #expect(report.lines.count == 2)
        #expect(report.lines[0].index == 1)
        #expect(report.lines[0].isTrue)
        #expect(report.lines[0].reason == "true")
        #expect(report.lines[0].text == "GetGlobalValue == 1")
        #expect(report.lines[1].index == 2)
        #expect(!report.lines[1].isTrue)
        // The Creation Kit spells this index 4096 higher than the on-disk one.
        #expect(report.lines[1].reason == "unimplemented function 14095")
    }

    /// A false condition is a different fact from an unevaluatable one, and the
    /// reason column is the only place that distinction survives.
    @Test
    func aCleanFalseReadsAsFalseRatherThanAsAFailure() throws {
        let conditions = try [
            ConditionEvaluatorFixture.comparing(
                functionIndex: Self.getGlobalValue, 0, 99,
                parameter1: ConditionEvaluatorFixture.flagFormID
            )
        ]
        var tally = ConditionTally()
        let report = try RuntimeStateConditionRunner.report(
            source: "MUSTest",
            conditions: conditions,
            context: ConditionEvaluatorFixture.populatedContext(),
            tally: &tally
        )
        #expect(report.lines.map(\.reason) == ["false"])
        #expect(tally.failureTotal == 0)
    }

    /// OR grouping: `A AND B(or) C` is `A AND (B OR C)`. The runner must agree
    /// with the evaluator's own list entry point on every one of those shapes.
    @Test
    func verdictMatchesTheEvaluatorForOrGroupedLists() throws {
        // Every true/false combination for the three conditions, expressed as
        // the comparison value each uses: 1 compares true, 0 compares false.
        for mask in 0 ..< 8 {
            let values = (0 ..< 3).map { Float((mask >> $0) & 1) }
            let conditions = try [
                Self.globalCompare(values[0]),
                Self.globalCompare(values[1], flags: 0x01),
                Self.globalCompare(values[2])
            ]
            var runnerTally = ConditionTally()
            let report = try RuntimeStateConditionRunner.report(
                source: "MUSTest",
                conditions: conditions,
                context: ConditionEvaluatorFixture.populatedContext(),
                tally: &runnerTally
            )
            var evaluator = try ConditionEvaluatorFixture.evaluator()
            let reference = evaluator.evaluate(conditions)
            #expect(report.isSatisfied == reference.isTrue, "mask \(mask)")
        }
    }

    /// An empty list is true, which is what an unconditioned record means.
    @Test
    func emptyListIsSatisfied() throws {
        var tally = ConditionTally()
        let report = try RuntimeStateConditionRunner.report(
            source: "MUSTEmpty",
            conditions: [],
            context: ConditionEvaluatorFixture.populatedContext(),
            tally: &tally
        )
        #expect(report.isSatisfied)
        #expect(report.lines.isEmpty)
        #expect(tally.listsEvaluated == 1)
        #expect(tally.conditionsEvaluated == 0)
    }

    /// The tally is a session counter, not a per-list one: the panel readout
    /// reports what the whole session has evaluated.
    @Test
    func tallyAccumulatesAcrossEvaluations() throws {
        let conditions = try [
            ConditionEvaluatorFixture.comparing(functionIndex: Self.unimplemented, 0, 1)
        ]
        var tally = ConditionTally()
        let context = try ConditionEvaluatorFixture.populatedContext()
        _ = RuntimeStateConditionRunner.report(
            source: "MUSTest", conditions: conditions, context: context, tally: &tally
        )
        let second = RuntimeStateConditionRunner.report(
            source: "MUSTest", conditions: conditions, context: context, tally: &tally
        )
        #expect(tally.conditionsEvaluated == 2)
        #expect(tally.listsEvaluated == 2)
        #expect(tally.failureTotal == 2)
        #expect(second.tallyLines.first == "Conditions evaluated: 2  Lists: 2")
        #expect(second.tallyLines.contains("Failures: 2"))
        #expect(second.tallyLines.contains { $0.hasPrefix("Unimplemented: ") })
    }

    /// A clean run states the two totals and nothing else, so the readout is
    /// two lines rather than a wall of zeroes.
    @Test
    func cleanTallyOmitsEmptyBuckets() {
        var tally = ConditionTally()
        tally.noteCondition()
        tally.noteList()
        #expect(RuntimeStateConditionRunner.tallyLines(tally) == [
            "Conditions evaluated: 1  Lists: 1",
            "Failures: 0"
        ])
    }

    @Test
    func failureDescriptionsNameTheirCause() {
        #expect(
            RuntimeStateConditionRunner.describe(.unavailableClock)
                == "no game clock in the evaluation context"
        )
        #expect(
            RuntimeStateConditionRunner.describe(.unresolvedGlobal(FormID(0x0000_003A)))
                == "unresolved global 0000003A"
        )
        #expect(
            RuntimeStateConditionRunner.describe(.unsupportedRunOn(.packageData))
                == "unsupported run-on packageData"
        )
        #expect(
            RuntimeStateConditionRunner.describe(.unknownOperator(6))
                == "undefined comparison operator 6"
        )
    }

    // MARK: Synthetic engine state

    //
    // Invented values. `OpenSkyTestFlag` is a synthetic GLOB defined by
    // `ConditionEvaluatorFixture`; nothing here comes from a game file.

    /// `GetGlobalValue(OpenSkyTestFlag) == value`, which is true only when
    /// `value` is the flag's synthetic value of 1.
    private static func globalCompare(_ value: Float, flags: UInt8 = 0) throws -> Condition {
        try ConditionEvaluatorFixture.condition(
            operatorBits: 0,
            flags: flags,
            comparisonValue: value.bitPattern,
            functionIndex: getGlobalValue,
            parameter1: ConditionEvaluatorFixture.flagFormID
        )
    }
}
