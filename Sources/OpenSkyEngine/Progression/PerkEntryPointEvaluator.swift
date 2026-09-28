// The perk entry-point evaluator (issue #497, roadmap item 20.4): given a
// number a formula is about to use and the perk effects that hook the entry
// point it is asking about, what number should the formula use instead.
//
// Pure arithmetic over values, with no store, no world and no conditions in it.
// Whether an effect is owned and whether its condition tabs pass is the
// runtime's question (`PerkRuntime`); this file answers only "what does this
// function do to this value", which is what makes every rule below a plain
// assertion in a test rather than something only a running session can show.
//
// ## The functions, quoted
//
// UESP "Skyrim Mod:Mod File Format/PERK", "Function Types", gives the new value
// per function id verbatim, and this is the whole table:
//
//   01 Set Value                VALUE
//   02 Add Value                Value + AMOUNT
//   03 Multiply Value           Value * FACTOR
//   04 Add Range to Value       Value + random(MIN, MAX)
//   05 Add Actor Value Mult     Value + AV * FACTOR
//   06 Absolute                 Abs(Value)
//   07 Negative ABS Value       -Abs(Value)
//   08 Add Level List           (list-valued, not a number)
//   09 Add Activate Choice      (button-valued, not a number)
//   0A Select Spell             (spell-valued, not a number)
//   0B Select Text              (text-valued, not a number)
//   0C Set AV Mult              AV * FACTOR
//   0D Multiply AV Mult         Value * AV * FACTOR
//   0E Multiply 1 + AV Mult     Value * (1 + AV * FACTOR)
//   0F Set Text                 (text-valued, not a number)
//
// Nine of the fifteen produce a number and are implemented. The five
// list-, spell-, button- and text-valued functions are not numbers at all: the
// perk effects that carry them hook entry points a formula never asks a float
// of (Apply Combat Hit Spell casts a spell, Set Activate Label writes a button
// label), so they are reported as `unsupportedFunction` and leave the value
// exactly as it arrived rather than being folded in as a zero.
//
// `Add Range to Value` is the one *numeric* function left out. Neither UESP nor
// xEdit documents the distribution or where the draw is seeded from, and
// inventing one would make a formula that is supposed to be reproducible depend
// on a number this engine made up. It is reported and skipped, and the count is
// what would justify implementing it.
//
// ## Ordering
//
// The PRKE priority byte is the only ordering the record carries, and UESP is
// candid about it: "Priority - Assumed to be how to order/iterate through perk
// sections". So the evaluator applies effects in descending priority, with ties
// broken by the caller's order — which `PerkStore`'s entry-point index has
// already fixed to (priority, plugin, object id, effect position), so the same
// load order always folds the same effects in the same sequence. Ordering only
// changes an answer when a `Set Value` competes with something else, since
// addition and multiplication over the rest commute; the choice is recorded in
// docs/engine/perks.md rather than presented as certain.
//
// Documented in docs/engine/perks.md.

import Foundation

/// One perk effect as the evaluator sees it: the function to apply, the payload
/// it reads, and the priority it declared.
nonisolated struct PerkEntryPointOperand: Equatable, Sendable {
    let function: PerkFunction
    /// EPFD as decoded, or nil when the effect carried none.
    let data: PerkFunctionData?
    /// PRKE byte 2, verbatim.
    let priority: UInt8
    /// The perk the effect belongs to, carried for reporting only. Nil for a
    /// hand-built operand in a test.
    let perk: ReferenceKey?

    init(
        function: PerkFunction,
        data: PerkFunctionData?,
        priority: UInt8 = 0,
        perk: ReferenceKey? = nil
    ) {
        self.function = function
        self.data = data
        self.priority = priority
        self.perk = perk
    }
}

/// Why one operand did not move the value. Every case is a counted no-op, never
/// an error and never a zero folded into the formula.
///
/// The `Error` conformance exists only so these can ride in a `Result`, which
/// is the same reason `ConditionFailure` carries one; nothing here ever throws
/// and no caller should catch one.
nonisolated enum PerkEntryPointSkip: Equatable, Error, Sendable {
    /// A function that produces something other than a number, or the one
    /// numeric function whose randomness is undocumented. See the file header.
    case unsupportedFunction(PerkFunction)
    /// The function needs an EPFD payload and the effect carried none, or
    /// carried one of the wrong shape for its declared function.
    case missingData(PerkFunction)
    /// An actor-value function whose value the caller could not read.
    case unavailableActorValue(Int32)
    /// The arithmetic produced an infinity or a NaN, which only a mod-authored
    /// payload can do. The value is left as it arrived.
    case nonFiniteResult(PerkFunction)
}

/// What one evaluation did.
nonisolated struct PerkEntryPointOutcome: Equatable, Sendable {
    /// The value after every applicable effect folded in.
    let value: Float
    /// The value the caller handed in, so a readout can show both.
    let input: Float
    /// How many operands actually moved the value.
    let applied: Int
    /// Every operand that did not, in evaluation order.
    let skipped: [PerkEntryPointSkip]

    /// Whether any perk changed the number.
    var didChange: Bool {
        value != input
    }
}

nonisolated enum PerkEntryPointEvaluator {
    /// Folds every operand into `value`, in the documented order.
    ///
    /// - Parameter actorValue: reads one of the owner's actor values by vanilla
    ///   index, for the four `AV` functions. Answering nil is a counted skip
    ///   rather than a zero, because a zero would silently turn
    ///   `Value * AV * FACTOR` into a wipe.
    static func evaluate(
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
    static func ordered(_ operands: [PerkEntryPointOperand]) -> [PerkEntryPointOperand] {
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
    static func apply(
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
    /// the arithmetic. Quoted per case in the file header.
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
