// ConditionEvaluator coverage: the comparison matrix, use-global resolution,
// OR grouping, and one end-to-end run from CTDA field bytes.
//
// Every condition here is built as real 32-byte CTDA bytes and decoded, so a
// layout change breaks these tests too. Documented semantics under test are
// cited in the ConditionEvaluator.swift header (UESP "CTDA Field", Creation Kit
// wiki "Conditions").

import Foundation
@testable import opensky
import Testing

struct ConditionEvaluatorTests {
    // MARK: - Fixtures

    /// `GetGlobalValue`, raw index (Creation Kit 4170).
    private static let getGlobalValue: UInt16 = 74
    private static let flagFormID = ConditionEvaluatorFixture.flagFormID
    private static let halfFormID = ConditionEvaluatorFixture.halfFormID

    private func evaluator() throws -> ConditionEvaluator {
        try ConditionEvaluator(
            context: ConditionContext(globals: ConditionEvaluatorFixture.standardGlobals())
        )
    }

    /// `GetGlobalValue(Flag) == 1` when `value` is true, `== 0` when false.
    /// `isOr` sets the OR flag, which joins this condition with the next.
    private func boolean(_ value: Bool, isOr: Bool = false) throws -> Condition {
        try ConditionEvaluatorFixture.condition(
            operatorBits: 0,
            flags: isOr ? 0x01 : 0,
            comparisonValue: (value ? Float(1) : Float(0)).bitPattern,
            functionIndex: Self.getGlobalValue,
            parameter1: Self.flagFormID
        )
    }

    // MARK: - Operator matrix

    @Test func evaluatesEveryOperatorAgainstBelowEqualAndAbove() throws {
        // Left-hand side is the Flag global, which is 1. Right-hand sides are
        // below it, equal to it, and above it.
        let rights: [Float] = [0.5, 1, 2]
        let expected: [UInt8: [Bool]] = [
            0: [false, true, false], // equal
            1: [true, false, true], // not equal
            2: [true, false, false], // greater than
            3: [true, true, false], // greater than or equal
            4: [false, false, true], // less than
            5: [false, true, true] // less than or equal
        ]
        var evaluator = try evaluator()
        for (bits, wanted) in expected.sorted(by: { $0.key < $1.key }) {
            for (index, right) in rights.enumerated() {
                let condition = try ConditionEvaluatorFixture.comparing(
                    functionIndex: Self.getGlobalValue,
                    bits,
                    right,
                    parameter1: Self.flagFormID
                )
                let outcome = evaluator.evaluate(condition)
                #expect(
                    outcome.isTrue == wanted[index],
                    "operator \(bits) against \(right) should be \(wanted[index])"
                )
                #expect(outcome.isConclusive)
            }
        }
        #expect(evaluator.tally.isClean)
        #expect(evaluator.tally.conditionsEvaluated == 18)
    }

    @Test func comparesFloatsExactlyWithNoEpsilon() throws {
        var evaluator = try evaluator()
        // 0.5 is exactly representable, so equality holds; 0.5000001 is a
        // different float and equality must not be fudged into true.
        let exact = try ConditionEvaluatorFixture.comparing(
            functionIndex: Self.getGlobalValue, 0, 0.5, parameter1: Self.halfFormID
        )
        let near = try ConditionEvaluatorFixture.comparing(
            functionIndex: Self.getGlobalValue, 0, 0.500_000_1, parameter1: Self.halfFormID
        )
        #expect(evaluator.evaluate(exact).isTrue)
        #expect(!evaluator.evaluate(near).isTrue)
    }

    @Test func unknownOperatorIsTaggedFalse() throws {
        var evaluator = try evaluator()
        for bits: UInt8 in [6, 7] {
            let condition = try ConditionEvaluatorFixture.comparing(
                functionIndex: Self.getGlobalValue, bits, 1, parameter1: Self.flagFormID
            )
            let outcome = evaluator.evaluate(condition)
            #expect(!outcome.isTrue)
            #expect(outcome.failures == [.unknownOperator(bits)])
        }
        #expect(evaluator.tally.unknownOperatorTotal == 2)
        #expect(evaluator.tally.unknownOperators == [6: 1, 7: 1])
        #expect(!evaluator.tally.isClean)
    }

    // MARK: - Use-global comparison values

    @Test func resolvesUseGlobalComparisonValue() throws {
        var evaluator = try evaluator()
        // Flag (1) is greater than Half (0.5); flag 0x04 retypes the comparison
        // word from a float into the GLOB FormID to read.
        let greater = try ConditionEvaluatorFixture.condition(
            operatorBits: 2,
            flags: 0x04,
            comparisonValue: Self.halfFormID,
            functionIndex: Self.getGlobalValue,
            parameter1: Self.flagFormID
        )
        let equal = try ConditionEvaluatorFixture.condition(
            operatorBits: 0,
            flags: 0x04,
            comparisonValue: Self.flagFormID,
            functionIndex: Self.getGlobalValue,
            parameter1: Self.flagFormID
        )
        #expect(evaluator.evaluate(greater).isTrue)
        #expect(evaluator.evaluate(equal).isTrue)
        #expect(evaluator.tally.isClean)
    }

    @Test func unresolvedUseGlobalIsTaggedFalseRatherThanZero() throws {
        var evaluator = try evaluator()
        let missing: UInt32 = 0x0000_0999
        // Flag is 1, so comparing "> missing" would be true if an unresolved
        // global silently read as 0. It must be unevaluatable instead.
        let condition = try ConditionEvaluatorFixture.condition(
            operatorBits: 2,
            flags: 0x04,
            comparisonValue: missing,
            functionIndex: Self.getGlobalValue,
            parameter1: Self.flagFormID
        )
        let outcome = evaluator.evaluate(condition)
        #expect(!outcome.isTrue)
        #expect(outcome.failures == [.unresolvedGlobal(FormID(missing))])
        #expect(evaluator.tally.unresolvedGlobalTotal == 1)
        #expect(evaluator.tally.rankedUnresolvedGlobals.map(\.count) == [1])
    }

    // MARK: - List logic and OR grouping

    @Test func emptyConditionListIsTrue() throws {
        var evaluator = try evaluator()
        let outcome = evaluator.evaluate([])
        #expect(outcome.isTrue)
        #expect(outcome.isConclusive)
        #expect(evaluator.tally.listsEvaluated == 1)
        #expect(evaluator.tally.conditionsEvaluated == 0)
    }

    @Test func andsConditionsWithoutOrFlag() throws {
        let cases: [([Bool], Bool)] = [
            ([true], true),
            ([false], false),
            ([true, true], true),
            ([true, false], false),
            ([false, true], false),
            ([false, false], false),
            ([true, true, true], true)
        ]
        for (values, wanted) in cases {
            var evaluator = try evaluator()
            let conditions = try values.map { try boolean($0) }
            #expect(evaluator.evaluate(conditions).isTrue == wanted, "\(values)")
        }
    }

    /// The Creation Kit wiki's documented example: `A AND B(or) C AND D`
    /// evaluates as `A AND (B OR C) AND D`.
    @Test func groupsOrFlaggedConditionsTighterThanAnd() throws {
        for mask in 0 ..< 16 {
            let values = (0 ..< 4).map { mask & (1 << $0) != 0 }
            var evaluator = try evaluator()
            let conditions = try [
                boolean(values[0]),
                boolean(values[1], isOr: true),
                boolean(values[2]),
                boolean(values[3])
            ]
            let wanted = values[0] && (values[1] || values[2]) && values[3]
            #expect(
                evaluator.evaluate(conditions).isTrue == wanted,
                "A=\(values[0]) B=\(values[1]) C=\(values[2]) D=\(values[3])"
            )
        }
    }

    @Test func chainsConsecutiveOrFlagsIntoOneBlock() throws {
        for mask in 0 ..< 8 {
            let values = (0 ..< 3).map { mask & (1 << $0) != 0 }
            var evaluator = try evaluator()
            let conditions = try [
                boolean(values[0], isOr: true),
                boolean(values[1], isOr: true),
                boolean(values[2])
            ]
            let wanted = values[0] || values[1] || values[2]
            #expect(evaluator.evaluate(conditions).isTrue == wanted, "\(values)")
        }
    }

    /// An OR flag on the last condition has no following operator to replace,
    /// so the block simply ends there rather than dangling or wrapping.
    @Test func trailingOrFlagEndsTheBlock() throws {
        let cases: [([Bool], Bool)] = [
            ([true, false], true), // (A OR B) with nothing following
            ([false, false], false),
            ([false, true], true)
        ]
        for (values, wanted) in cases {
            var evaluator = try evaluator()
            let conditions = try [boolean(values[0], isOr: true), boolean(values[1], isOr: true)]
            #expect(evaluator.evaluate(conditions).isTrue == wanted, "\(values)")
        }

        // A single trailing-OR condition is its own whole block.
        var single = try evaluator()
        #expect(try single.evaluate([boolean(true, isOr: true)]).isTrue)
        #expect(try !single.evaluate([boolean(false, isOr: true)]).isTrue)
    }

    @Test func evaluatesEveryConditionWithoutShortCircuiting() throws {
        // The first condition already decides the list, but the tally must
        // still see all three: coverage evidence is the point of the tally.
        var evaluator = try evaluator()
        let conditions = try [boolean(false), boolean(true), boolean(true)]
        #expect(!evaluator.evaluate(conditions).isTrue)
        #expect(evaluator.tally.conditionsEvaluated == 3)
        #expect(evaluator.tally.listsEvaluated == 1)
    }

    @Test func collectsFailuresFromEveryUnevaluatableCondition() throws {
        var evaluator = try evaluator()
        let conditions = try [
            boolean(true),
            ConditionEvaluatorFixture.comparing(functionIndex: 9999, 0, 1),
            ConditionEvaluatorFixture.comparing(functionIndex: 8888, 0, 1)
        ]
        let outcome = evaluator.evaluate(conditions)
        #expect(!outcome.isTrue)
        #expect(outcome.failures == [.unknownFunction(9999), .unknownFunction(8888)])
        #expect(!outcome.isConclusive)
    }

    // MARK: - End to end

    /// A MUST-style condition run: raw CITC/CTDA bytes decoded through
    /// `ConditionList`, then evaluated.
    @Test func decodesAndEvaluatesConditionRunFromFieldBytes() throws {
        var list = ConditionList()
        var count = Data()
        count.appendUInt32(3)
        try list.decode(field: ESMField(type: "CITC", data: count))
        // GetCurrentTime >= 6 AND (GetGlobalValue(Flag) == 0 OR
        // GetGlobalValue(Flag) == 1)
        try list.decode(field: ConditionEvaluatorFixture.field(
            operatorBits: 3, comparisonValue: Float(6).bitPattern, functionIndex: 18
        ))
        try list.decode(field: ConditionEvaluatorFixture.field(
            operatorBits: 0,
            flags: 0x01,
            comparisonValue: Float(0).bitPattern,
            functionIndex: Self.getGlobalValue,
            parameter1: Self.flagFormID
        ))
        try list.decode(field: ConditionEvaluatorFixture.field(
            operatorBits: 0,
            comparisonValue: Float(1).bitPattern,
            functionIndex: Self.getGlobalValue,
            parameter1: Self.flagFormID
        ))
        #expect(list.declaredCount == 3)
        #expect(list.conditions.count == 3)

        var morning = try ConditionEvaluator(context: ConditionContext(
            globals: ConditionEvaluatorFixture.standardGlobals(), clock: GameClock(hour: 9)
        ))
        let day = morning.evaluate(list)
        #expect(day.isTrue)
        #expect(day.isConclusive)
        #expect(morning.tally.isClean)

        // Before 06:00 the first block fails, so the whole run is false even
        // though the OR block still passes.
        var night = try ConditionEvaluator(context: ConditionContext(
            globals: ConditionEvaluatorFixture.standardGlobals(), clock: GameClock(hour: 3)
        ))
        #expect(!night.evaluate(list).isTrue)
        #expect(night.tally.isClean)
        #expect(night.tally.conditionsEvaluated == 3)
    }
}
