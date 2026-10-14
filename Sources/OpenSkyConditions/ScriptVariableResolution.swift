// Papyrus variables a condition can read: `GetVMQuestVariable` and
// `GetVMScriptVariable`. The scripting module fills it on the main actor.
// See docs/engine/condition-functions.md#script-variables.

import Foundation
import OpenSkyFormatsESM

/// The number variables of each script-carrying object, by folded variable name.
nonisolated public struct ScriptVariableResolution: ConditionResolution, Sendable {
    public static let empty = ScriptVariableResolution()

    private let values: [ReferenceKey: [String: Float]]
    public let isAvailable: Bool

    /// `values` holds names already folded to lowercase.
    public init(values: [ReferenceKey: [String: Float]]) {
        self.values = values
        isAvailable = true
    }

    private init() {
        values = [:]
        isAvailable = false
    }

    /// Nil when no script on `owner` declares `name`, or the variable is not a number.
    public func value(named name: String, on owner: ReferenceKey) -> Float? {
        values[owner]?[name.lowercased()]
    }
}

nonisolated extension ConditionContext {
    public var scriptVariables: ScriptVariableResolution {
        get { self[resolution: ScriptVariableResolution.self] }
        set { self[resolution: ScriptVariableResolution.self] = newValue }
    }
}

nonisolated extension ConditionFunctions {
    public static func installScriptVariables(_ registry: inout ConditionFunctionRegistry) {
        // Parameter 1 names the object; `CIS2` names the variable, such as
        // "::bAllTargetsInTrigger_var" (<https://ck.uesp.net/wiki/GetVMScriptVariable>).
        registry.register(ConditionFunction(
            index: 630, name: "GetVMScriptVariable", parameter1: .formID
        ) { call in
            guard let owner = Self.parameterKey(call, call.parameter1) else {
                return .failure(.unresolvedParameter(630))
            }
            return Self.scriptVariable(call, on: owner)
        })
    }

    /// The variable `CIS2` names on `owner`. The raw parameter word is not a name.
    public static func scriptVariable(
        _ call: ConditionCall, on owner: ReferenceKey
    ) -> Result<Float, ConditionFailure> {
        guard let name = call.condition.parameter2Name else {
            return .failure(.unresolvedParameter(call.condition.functionIndex))
        }
        guard let value = call.context.scriptVariables.value(named: name, on: owner) else {
            return .failure(.unavailableData(.scriptVariable))
        }
        return .success(value)
    }
}
