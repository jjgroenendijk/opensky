// `hkbEvaluateExpressionModifier` and `hkbEventsFromRangeModifier`: the two
// modifiers that turn variable values into assignments and events.

import Foundation
import OpenSkyFormatsAnimation

/// `hkbExpressionData::m_eventMode` and `hkbEventRangeData::m_eventMode` values.
nonisolated enum BehaviorExpressionEventMode {
    static let sendOnce = 0
    static let sendOnTrue = 1
    static let sendOnFalseToTrue = 2
    static let sendEveryFrameOnceTrue = 3
    static let sendOnEnterRange = 0
}

nonisolated extension BehaviorGraphInstance {
    /// Runs every statement of the modifier's expression array, in order, so a
    /// later statement sees what an earlier one assigned.
    func applyExpressions(
        _ modifier: HKBEvaluateExpressionModifier, _ step: BehaviorModifierStep
    ) {
        guard
            let arrayTarget = modifier.expressions,
            let array = object(at: arrayTarget, as: HKBExpressionDataArray.self)
        else { return }
        markReached(arrayTarget)
        let statements = statements(of: array, at: arrayTarget)
        var state = markReached(step.target)
        let count = array.expressionsData.count
        if state.flags.count != count {
            state.flags = Array(repeating: false, count: count)
            state.sentFlags = Array(repeating: false, count: count)
        }
        for (index, data) in array.expressionsData.enumerated() {
            guard let statement = statements[index] else {
                tally.note(.expressionUnparsed)
                continue
            }
            run(statement, mode: data.eventMode, slot: index, state: &state)
        }
        nodeStates[step.target] = state
    }

    private func statements(
        of array: HKBExpressionDataArray, at target: HKXPointerTarget
    ) -> [BehaviorExpressionStatement?] {
        if let cached = statementCache[target] {
            return cached
        }
        let parsed = array.expressionsData.map { data in
            data.expression.flatMap(BehaviorExpressionStatement.parse)
        }
        statementCache[target] = parsed
        return parsed
    }

    private func run(
        _ statement: BehaviorExpressionStatement,
        mode: Int,
        slot: Int,
        state: inout BehaviorNodeState
    ) {
        let lookup: (String) -> Float? = { [variables] in variables.value(of: $0)?.realValue }
        switch statement {
        case let .assignment(name, expression):
            guard let index = variables.index(of: name), let value = expression.evaluate(lookup)
            else {
                tally.note(.expressionUnresolved)
                return
            }
            writeVariable(.real(value), at: index)
        case let .event(name, condition):
            guard let value = condition.evaluate(lookup) else {
                tally.note(.expressionUnresolved)
                return
            }
            let truth = value != 0
            let send = switch mode {
            case BehaviorExpressionEventMode.sendOnTrue: truth
            case BehaviorExpressionEventMode.sendOnFalseToTrue: truth && !state.flags[slot]
            case BehaviorExpressionEventMode.sendEveryFrameOnceTrue: truth || state.sentFlags[slot]
            default: truth && !state.sentFlags[slot]
            }
            state.flags[slot] = truth
            if send {
                state.sentFlags[slot] = true
                raiseOrReport(named: name)
            }
        }
    }

    /// Raises a graph event by name, or keeps it as unbound when the graph
    /// declares no such event, like a `SoundPlay.` request.
    func raiseOrReport(named name: String) {
        if !events.raise(named: name) {
            unboundEvents.append(name)
        }
    }

    /// `hkbEventsFromRangeModifier`: the bands run from `m_lowerBound` up through
    /// each range's `m_upperBound`. A range raises its event when the input
    /// enters its band, or on every update while inside it.
    func applyEventsFromRange(
        _ modifier: HKBEventsFromRangeModifier, _ step: BehaviorModifierStep
    ) {
        guard
            let rangesTarget = modifier.eventRanges,
            let ranges = object(at: rangesTarget, as: HKBEventRangeDataArray.self)
        else { return }
        markReached(rangesTarget)
        var state = markReached(step.target)
        let input = step.bound.float("inputValue", or: modifier.inputValue)
        var lower = step.bound.float("lowerBound", or: modifier.lowerBound)
        var band: Int?
        for (index, range) in ranges.eventData.enumerated() {
            if input >= lower, input <= range.upperBound {
                band = index
                break
            }
            lower = range.upperBound
        }
        if let band {
            let range = ranges.eventData[band]
            if
                range.eventMode != BehaviorExpressionEventMode.sendOnEnterRange
                || state.rangeIndex != band
            {
                raise(range.event)
            }
        }
        state.rangeIndex = band
        nodeStates[step.target] = state
    }
}
