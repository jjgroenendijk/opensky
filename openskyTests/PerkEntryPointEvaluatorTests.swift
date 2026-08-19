// The pure entry-point evaluator (issue #497, roadmap item 20.4): one operand
// per documented function, the ordering rule, and every counted no-op.
//
// Hand-computed expectations throughout — each `#expect` states the arithmetic
// UESP's "Function Types" table gives rather than whatever the implementation
// produces.

import Foundation
@testable import opensky
import Testing

struct PerkEntryPointEvaluatorTests {
    private func operand(
        _ function: PerkFunction,
        _ data: PerkFunctionData?,
        priority: UInt8 = 0
    ) -> PerkEntryPointOperand {
        PerkEntryPointOperand(function: function, data: data, priority: priority)
    }

    @Test
    func eachNumericFunctionAppliesItsDocumentedArithmetic() {
        // 01 Set Value -> VALUE
        #expect(
            PerkEntryPointEvaluator
                .evaluate(10, through: [operand(.setValue, .float(3))]).value == 3
        )
        // 02 Add Value -> Value + AMOUNT
        #expect(
            PerkEntryPointEvaluator
                .evaluate(10, through: [operand(.addValue, .float(2.5))]).value == 12.5
        )
        // 03 Multiply Value -> Value * FACTOR
        #expect(
            PerkEntryPointEvaluator
                .evaluate(10, through: [operand(.multiplyValue, .float(1.2))]).value == 12
        )
        // 06 Absolute -> Abs(Value)
        #expect(
            PerkEntryPointEvaluator
                .evaluate(-7, through: [operand(.absoluteValue, nil)]).value == 7
        )
        // 07 Negative ABS Value -> -Abs(Value)
        #expect(
            PerkEntryPointEvaluator
                .evaluate(7, through: [operand(.negativeAbsoluteValue, nil)]).value == -7
        )
    }

    @Test
    func theFourActorValueFunctionsReadTheValueTheyName() {
        let payload = PerkFunctionData.actorValueMultiplier(actorValue: 41, factor: 0.5)
        let read: (Int32) -> Float? = { $0 == 41 ? 20 : nil }

        // 05 Add Actor Value Mult -> Value + AV * FACTOR
        #expect(
            PerkEntryPointEvaluator.evaluate(
                4, through: [operand(.addActorValueMultiplier, payload)], actorValue: read
            ).value == 14
        )
        // 0C Set AV Mult -> AV * FACTOR
        #expect(
            PerkEntryPointEvaluator.evaluate(
                4, through: [operand(.setToActorValueMultiplier, payload)], actorValue: read
            ).value == 10
        )
        // 0D Multiply AV Mult -> Value * AV * FACTOR
        #expect(
            PerkEntryPointEvaluator.evaluate(
                4, through: [operand(.multiplyActorValueMultiplier, payload)], actorValue: read
            ).value == 40
        )
        // 0E Multiply 1 + AV Mult -> Value * (1 + AV * FACTOR)
        #expect(
            PerkEntryPointEvaluator.evaluate(
                4,
                through: [operand(.multiplyOnePlusActorValueMultiplier, payload)],
                actorValue: read
            ).value == 44
        )
    }

    /// A value nothing can read is a counted skip, not a zero: folding zero into
    /// `Value * AV * FACTOR` would wipe the formula instead of leaving it alone.
    @Test
    func anUnreadableActorValueLeavesTheValueAlone() {
        let outcome = PerkEntryPointEvaluator.evaluate(
            4,
            through: [operand(
                .multiplyActorValueMultiplier,
                .actorValueMultiplier(actorValue: 41, factor: 0.5)
            )],
            actorValue: { _ in nil }
        )

        #expect(outcome.value == 4)
        #expect(outcome.applied == 0)
        #expect(outcome.skipped == [.unavailableActorValue(41)])
        #expect(!outcome.didChange)
    }

    /// The five list-, spell-, button- and text-valued functions produce no
    /// number, and the one numeric function whose randomness is undocumented is
    /// refused with them.
    @Test
    func nonNumericFunctionsAndTheUndocumentedRangeAreCountedAndSkipped() {
        let unsupported: [PerkEntryPointOperand] = [
            operand(.addRangeToValue, .floatPair(1, 4)),
            operand(.addLeveledList, .leveledItem(FormID(0x10))),
            operand(.addActivateChoice, nil),
            operand(.selectSpell, .spell(FormID(0x11))),
            operand(.selectText, .text("GMST")),
            operand(.setText, .localizedText(.inline("Pick"))),
            operand(.unknown(raw: 99), nil)
        ]

        let outcome = PerkEntryPointEvaluator.evaluate(5, through: unsupported)

        #expect(outcome.value == 5)
        #expect(outcome.applied == 0)
        #expect(outcome.skipped.count == unsupported.count)
        #expect(outcome.skipped.allSatisfy {
            if case .unsupportedFunction = $0 {
                return true
            }
            return false
        })
    }

    @Test
    func aFunctionWithNoPayloadIsCountedRatherThanTreatedAsZero() {
        let outcome = PerkEntryPointEvaluator.evaluate(9, through: [operand(.multiplyValue, nil)])

        #expect(outcome.value == 9)
        #expect(outcome.skipped == [.missingData(.multiplyValue)])
    }

    /// A mod-authored payload that produces an infinity leaves the value as it
    /// arrived, so one bad record cannot poison a formula.
    @Test
    func aNonFiniteResultLeavesTheValueAsItArrived() {
        let outcome = PerkEntryPointEvaluator.evaluate(
            .greatestFiniteMagnitude,
            through: [operand(.multiplyValue, .float(.greatestFiniteMagnitude))]
        )

        #expect(outcome.value == .greatestFiniteMagnitude)
        #expect(outcome.skipped == [.nonFiniteResult(.multiplyValue)])
    }

    /// Descending priority, ties in the caller's order. It only shows when a
    /// `Set Value` competes: `set 5` then `add 1` is 6, the other way round is 5.
    @Test
    func operandsFoldInDescendingPriorityOrder() {
        let setFirst = PerkEntryPointEvaluator.evaluate(0, through: [
            operand(.addValue, .float(1), priority: 1),
            operand(.setValue, .float(5), priority: 9)
        ])
        #expect(setFirst.value == 6)

        let addFirst = PerkEntryPointEvaluator.evaluate(0, through: [
            operand(.addValue, .float(1), priority: 9),
            operand(.setValue, .float(5), priority: 1)
        ])
        #expect(addFirst.value == 5)
    }

    /// Equal priorities keep the caller's order, which is what makes
    /// `PerkStore`'s already-sorted index the deterministic sequence.
    @Test
    func equalPrioritiesKeepTheCallersOrder() {
        let ordered = PerkEntryPointEvaluator.ordered([
            operand(.setValue, .float(1), priority: 5),
            operand(.setValue, .float(2), priority: 5),
            operand(.setValue, .float(3), priority: 7)
        ])

        #expect(ordered.map(\.data) == [.float(3), .float(1), .float(2)])
    }

    @Test
    func anEntryPointNothingHooksLeavesTheValueUntouched() {
        let outcome = PerkEntryPointEvaluator.evaluate(12.5, through: [])

        #expect(outcome.value == 12.5)
        #expect(outcome.input == 12.5)
        #expect(!outcome.didChange)
        #expect(outcome.skipped.isEmpty)
    }
}
