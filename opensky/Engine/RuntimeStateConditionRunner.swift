// Turns a decoded condition list plus a live context into the per-condition
// report the World > Runtime State panel shows (issue #166, roadmap item
// 10.2.4).
//
// Why this exists rather than a direct call to `ConditionEvaluator`: the list
// entry point returns one verdict and a flattened `failures` array, which
// cannot say which condition produced which failure. The single-condition entry
// point does, so this runner evaluates each condition once and recombines the
// booleans with the same OR grouping `ConditionEvaluator.evaluate(_:)` applies.
// Evaluating both ways instead would count every condition twice in the tally
// and draw twice from the `ConditionRandom` stream, so `GetRandomPercent` would
// disagree with itself between the verdict and the reasons.
//
// The grouping rule is restated here from the evaluator's own implementation,
// not from memory: the OR flag on condition N joins it to condition N+1, blocks
// combine with AND, and a trailing OR flag closes its block with the list.
//
// No AppKit: this compiles into the app and the CLI target.
//
// Documented in docs/engine/runtime-state.md.

import Foundation

nonisolated enum RuntimeStateConditionRunner {
    /// Evaluates `conditions` against `context`, accumulating into `tally` so a
    /// session's counters span every evaluation the panel has run.
    static func report(
        source: String,
        conditions: [Condition],
        context: ConditionContext,
        tally: inout ConditionTally
    ) -> RuntimeStateConditionReport {
        var evaluator = ConditionEvaluator(context: context, tally: tally)
        var lines: [RuntimeStateConditionLine] = []
        var outcomes: [Bool] = []
        for (offset, condition) in conditions.enumerated() {
            let outcome = evaluator.evaluate(condition)
            outcomes.append(outcome.isTrue)
            lines.append(
                RuntimeStateConditionLine(
                    index: offset + 1,
                    text: describe(condition, registry: evaluator.registry),
                    isTrue: outcome.isTrue,
                    reason: reason(for: outcome)
                )
            )
        }
        tally = evaluator.tally
        tally.noteList()
        return RuntimeStateConditionReport(
            source: source,
            isSatisfied: combine(conditions: conditions, outcomes: outcomes),
            lines: lines,
            tallyLines: tallyLines(tally)
        )
    }

    /// The list verdict, reproducing `ConditionEvaluator.evaluate(_ conditions:)`
    /// exactly: an empty list is true, a block closes on the first condition
    /// without the OR flag, and a trailing OR flag closes the last block.
    static func combine(conditions: [Condition], outcomes: [Bool]) -> Bool {
        guard let last = conditions.last, conditions.count == outcomes.count else {
            return true
        }
        var result = true
        var block = false
        for (condition, isTrue) in zip(conditions, outcomes) {
            block = block || isTrue
            if !condition.flags.contains(.or) {
                result = result && block
                block = false
            }
        }
        if last.flags.contains(.or) {
            result = result && block
        }
        return result
    }

    // MARK: Formatting

    /// `<function> <operator> <right-hand side>` with an `(or)` marker, which
    /// is enough to recognise a condition without reproducing the Creation
    /// Kit's whole parameter vocabulary.
    static func describe(
        _ condition: Condition,
        registry: ConditionFunctionRegistry
    ) -> String {
        let name = registry.name(for: condition.functionIndex)
        let text = "\(name) \(symbol(condition.comparison)) \(rightHandSide(condition))"
        return condition.flags.contains(.or) ? text + " (or)" : text
    }

    static func symbol(_ comparison: Condition.ComparisonOperator) -> String {
        switch comparison {
        case .equal: "=="
        case .notEqual: "!="
        case .greaterThan: ">"
        case .greaterThanOrEqual: ">="
        case .lessThan: "<"
        case .lessThanOrEqual: "<="
        case let .unknown(raw): "operator \(raw)"
        }
    }

    static func rightHandSide(_ condition: Condition) -> String {
        switch condition.comparisonValue {
        case let .value(literal): RuntimeStateNumberText.text(literal)
        case let .global(id): "global \(id)"
        }
    }

    static func reason(for outcome: ConditionOutcome) -> String {
        guard let failure = outcome.failures.first else {
            return outcome.isTrue ? "true" : "false"
        }
        return describe(failure)
    }

    static func describe(_ failure: ConditionFailure) -> String {
        switch failure {
        case let .unknownFunction(index):
            "unimplemented function \(Int(index) + ConditionFunctionRegistry.creationKitOffset)"
        case let .unresolvedGlobal(id):
            "unresolved global \(id)"
        case let .unresolvedQuest(id):
            "unresolved quest \(id)"
        case let .unsupportedRunOn(runOn):
            "unsupported run-on \(ConditionTally.runOnName(runOn))"
        case let .unresolvedReference(runOn):
            "unresolved reference for run-on \(ConditionTally.runOnName(runOn))"
        case let .unknownOperator(bits):
            "undefined comparison operator \(bits)"
        case let .unresolvedParameter(index):
            "unresolved parameter for function "
                + "\(Int(index) + ConditionFunctionRegistry.creationKitOffset)"
        case .unavailableClock:
            "no game clock in the evaluation context"
        }
    }

    /// The tally counters as readout lines. Buckets that never fired are
    /// omitted so a clean run reads as two lines rather than as a wall of
    /// zeroes.
    static func tallyLines(_ tally: ConditionTally) -> [String] {
        var lines = [
            "Conditions evaluated: \(tally.conditionsEvaluated)"
                + "  Lists: \(tally.listsEvaluated)",
            "Failures: \(tally.failureTotal)"
        ]
        lines.append(contentsOf: ranked("Unimplemented", tally.rankedUnknownFunctions()))
        lines.append(contentsOf: ranked("Unresolved globals", tally.rankedUnresolvedGlobals))
        lines.append(contentsOf: ranked("Unresolved quests", tally.rankedUnresolvedQuests))
        lines.append(contentsOf: ranked("Unsupported run-ons", tally.rankedUnsupportedRunOns))
        lines.append(
            contentsOf: ranked("Unresolved references", tally.rankedUnresolvedReferences)
        )
        if tally.unknownOperatorTotal > 0 {
            lines.append("Undefined operators: \(tally.unknownOperatorTotal)")
        }
        if tally.unresolvedParameterTotal > 0 {
            lines.append("Unresolved parameters: \(tally.unresolvedParameterTotal)")
        }
        if tally.unavailableClock > 0 {
            lines.append("Clock unavailable: \(tally.unavailableClock)")
        }
        return lines
    }

    private static func ranked(
        _ label: String,
        _ entries: [(name: String, count: Int)]
    ) -> [String] {
        guard !entries.isEmpty else { return [] }
        let text = entries.prefix(4).map { "\($0.name) x\($0.count)" }.joined(separator: ", ")
        return ["\(label): \(text)"]
    }
}
