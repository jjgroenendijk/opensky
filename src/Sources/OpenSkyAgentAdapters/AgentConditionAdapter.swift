// `openskycli game state condition`: one condition function, run on a loaded reference
// against the live condition context, the one AI packages and dialogue read.

import Foundation
import OpenSkyAgentControl
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkySessionInterface

extension AgentWorldAdapter {
    func conditionState(_ probe: AgentConditionProbe) throws(AgentFailure) -> AgentJSON {
        guard let index = Self.conditionFunctionIndex(named: probe.function) else {
            throw AgentFailure(
                .invalidArgument, "unknown condition function '\(probe.function)'"
            )
        }
        let subject = try hub.resolveReference(probe.reference)
        let target = try probe.target.map { text throws(AgentFailure) in
            try hub.resolveReference(text)
        }
        var evaluator = ConditionEvaluator(context: game.runtimeState.conditionContext(
            indexing: [subject.key] + (target.map { [$0.key] } ?? [])
        ))
        evaluator.context.subject = subject.key
        evaluator.context.target = target?.key
        let function = evaluator.context.functions[index]
        let raw = try probe.parameter.map { text throws(AgentFailure) in
            try Self.conditionParameter(text, isFormID: function?.parameter1 == .formID)
        } ?? 0
        let raw2 = try probe.parameter2.map { text throws(AgentFailure) in
            try Self.conditionParameter(text, isFormID: function?.parameter2 == .formID)
        } ?? 0
        let outcome = evaluator.value(
            of: Condition(probingFunction: index, parameter1: raw, parameter2: raw2)
        )
        var answer: [String: AgentJSON] = [
            "function": .init(ConditionFunctionNames.name(for: index)),
            "ref": .formID(subject.formID.rawValue),
            "value": .null, "failure": .null
        ]
        switch outcome {
        case let .success(value): answer["value"] = .init(value)
        case let .failure(failure): answer["failure"] = .string(String(describing: failure))
        }
        return .object(answer)
    }

    /// The stored index of a function by its Creation Kit name, in any case.
    static func conditionFunctionIndex(named name: String) -> UInt16? {
        (0 ... lastConditionFunctionIndex).first {
            ConditionFunctionNames.name(for: $0)?.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    /// Above the highest stored index any table lists, the SKSE ones included.
    private static let lastConditionFunctionIndex: UInt16 = 2048

    /// A FormID parameter in hex, as the console takes it; any other as a whole number.
    static func conditionParameter(
        _ text: String, isFormID: Bool
    ) throws(AgentFailure) -> UInt32 {
        if isFormID {
            guard let formID = FormID(hexText: text) else {
                throw AgentFailure(.invalidArgument, "param '\(text)' is not a hex FormID")
            }
            return formID.rawValue
        }
        guard let number = Int32(text) else {
            throw AgentFailure(.invalidArgument, "param '\(text)' is not a whole number")
        }
        return UInt32(bitPattern: number)
    }
}
