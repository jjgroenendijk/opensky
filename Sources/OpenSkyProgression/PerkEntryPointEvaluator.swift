// Applies the perk effects of one entry point to the value a formula is about to
// use. `PerkRuntime` decides which effects the actor owns and which pass their
// conditions. The function table and the priority order are in
// docs/engine/perks.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyProgressionInterface

nonisolated public enum PerkEntryPointEvaluator: Sendable {
    /// Folds every operand into `value`, in the documented order.
    ///
    /// - Parameter actorValue: reads one of the owner's actor values by vanilla
    ///   index, for the four `AV` functions. Answering nil is a counted skip
    ///   rather than a zero, because a zero would silently turn
    ///   `Value * AV * FACTOR` into a wipe.
    public static func evaluate(
        _ value: Float,
        through operands: [PerkEntryPointOperand],
        actorValue: (Int32) -> Float? = { _ in nil }
    ) -> PerkEntryPointOutcome {
        var current = value.isFinite ? value : 0
        var applied = 0
        var skipped: [PerkEntryPointSkip] = []
        for operand in ordered(operands) {
            switch apply(operand, to: current, actorValue: actorValue) {
            case let .success(result):
                if result != current {
                    applied += 1
                }
                current = result
            case let .failure(skip):
                skipped.append(skip)
            }
        }
        return PerkEntryPointOutcome(
            value: current,
            input: value,
            applied: applied,
            skipped: skipped
        )
    }

    /// Descending priority, ties in the caller's order.
    ///
    /// Sorted on the index alongside the element because Swift's `sort` is not
    /// guaranteed stable, and an unstable tie-break would make the same load
    /// order fold the same effects in a different sequence between runs.
    public static func ordered(_ operands: [PerkEntryPointOperand]) -> [PerkEntryPointOperand] {
        operands
            .enumerated()
            .sorted {
                $0.element.priority == $1.element.priority
                    ? $0.offset < $1.offset
                    : $0.element.priority > $1.element.priority
            }
            .map(\.element)
    }

    /// One operand applied to one value.
    public static func apply(
        _ operand: PerkEntryPointOperand,
        to value: Float,
        actorValue: (Int32) -> Float?
    ) -> Result<Float, PerkEntryPointSkip> {
        switch operand.function {
        case .setValue:
            finite(operand, float(operand).map(\.self))
        case .addValue:
            finite(operand, float(operand).map { value + $0 })
        case .multiplyValue:
            finite(operand, float(operand).map { value * $0 })
        case .absoluteValue:
            finite(operand, abs(value))
        case .negativeAbsoluteValue:
            finite(operand, -abs(value))
        case .addActorValueMultiplier,
             .setToActorValueMultiplier,
             .multiplyActorValueMultiplier,
             .multiplyOnePlusActorValueMultiplier:
            actorValueResult(operand, value: value, actorValue: actorValue)
        case .addRangeToValue,
             .addLeveledList,
             .addActivateChoice,
             .selectSpell,
             .selectText,
             .setText,
             .unknown:
            .failure(.unsupportedFunction(operand.function))
        }
    }

    // MARK: - Private

    /// The four `AV` functions, which share a payload shape and differ only in
    /// the arithmetic.
    private static func actorValueResult(
        _ operand: PerkEntryPointOperand,
        value: Float,
        actorValue: (Int32) -> Float?
    ) -> Result<Float, PerkEntryPointSkip> {
        guard case let .actorValueMultiplier(index, factor) = operand.data else {
            return .failure(.missingData(operand.function))
        }
        guard let read = actorValue(index), read.isFinite else {
            return .failure(.unavailableActorValue(index))
        }
        let product = read * factor
        let result: Float = switch operand.function {
        case .addActorValueMultiplier: value + product
        case .setToActorValueMultiplier: product
        case .multiplyActorValueMultiplier: value * product
        default: value * (1 + product)
        }
        return finite(operand, result)
    }

    /// The EPFD payload of a single-float function, or nil when the effect
    /// carried a payload of a different shape.
    ///
    /// A `floatPair` is accepted at its first component: a record whose EPFT
    /// declared a pair under a function that reads one float is exactly the
    /// disagreement `PerkEffect` keeps rather than resolves, and reading the
    /// first float is what the declared *function* asks for.
    private static func float(_ operand: PerkEntryPointOperand) -> Float? {
        switch operand.data {
        case let .float(value): value
        case let .floatPair(first, _): first
        default: nil
        }
    }

    private static func finite(
        _ operand: PerkEntryPointOperand,
        _ value: Float?
    ) -> Result<Float, PerkEntryPointSkip> {
        guard let value else { return .failure(.missingData(operand.function)) }
        guard value.isFinite else { return .failure(.nonFiniteResult(operand.function)) }
        return .success(value)
    }
}
