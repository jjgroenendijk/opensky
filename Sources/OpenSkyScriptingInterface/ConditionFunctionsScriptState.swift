// Condition functions that read what a script set with a native, such as `SetGhost` or
// `SetKeywordData`. The scripting module fills the snapshot on the main actor.
// See docs/engine/condition-functions.md#script-state.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

/// The script state of every form a script changed, keyed by that form.
nonisolated public struct ScriptedStateConditionResolution: ConditionResolution, Sendable {
    public static let empty = ScriptedStateConditionResolution(states: nil)

    private let states: [ReferenceKey: ScriptedReferenceState]?

    public init(states: [ReferenceKey: ScriptedReferenceState]?) {
        self.states = states
    }

    /// The state of `key`, empty when no script changed it. Nil when nothing was wired.
    public func state(of key: ReferenceKey) -> ScriptedReferenceState? {
        guard let states else { return nil }
        return states[key] ?? ScriptedReferenceState()
    }
}

nonisolated extension ConditionContext {
    public var scriptedState: ScriptedStateConditionResolution {
        get { self[resolution: ScriptedStateConditionResolution.self] }
        set { self[resolution: ScriptedStateConditionResolution.self] = newValue }
    }
}

/// The names natives store flags and values under, shared with the conditions.
nonisolated public enum ScriptedStateName: Sendable {
    public static let ghost = "ghost"
    public static let restrained = "restrained"
    public static let playerTeammate = "playerTeammate"
    public static let allowFlying = "allowFlying"
    public static let alerted = "alerted"
    public static let bribed = "bribed"
    public static let cleared = "cleared"
    public static let essential = "essential"
    public static let protected = "protected"

    /// The value `Location.SetKeywordData` stores for one keyword.
    public static func keywordData(_ keyword: ReferenceKey) -> String {
        "keywordData:\(keyword)"
    }
}

nonisolated extension ConditionFunctions {
    public static func installScriptState(_ registry: inout ConditionFunctionRegistry) {
        // The run-on's flag, false until a script sets it, as the matching native reads.
        let flags: [String: (index: UInt16, flag: String)] = [
            "GetIsAlerted": (91, ScriptedStateName.alerted),
            "GetIsGhost": (237, ScriptedStateName.ghost),
            "GetRestrained": (244, ScriptedStateName.restrained),
            "IsBribedbyPlayer": (402, ScriptedStateName.bribed),
            "GetPlayerTeammate": (453, ScriptedStateName.playerTeammate),
            "IsAllowedToFly": (698, ScriptedStateName.allowFlying)
        ]
        for (name, entry) in flags.sorted(by: { $0.key < $1.key }) {
            registry.register(ConditionFunction(index: entry.index, name: name) { call in
                call.referenceKey().flatMap { key in
                    Self.scriptState(call, of: key).map { Self.isTrue($0.flag(entry.flag) == true) }
                }
            })
        }
        // `ptLocation`; a location is cleared once a script calls `SetCleared`.
        registry.register(ConditionFunction(
            index: 250, name: "GetLocationCleared", parameter1: .formID
        ) { call in
            guard let location = Self.parameterKey(call, call.parameter1) else {
                return .failure(.unresolvedParameter(250))
            }
            return Self.scriptState(call, of: location).map {
                Self.isTrue($0.flag(ScriptedStateName.cleared) == true)
            }
        })
        installKeywordData(&registry)
    }

    /// Keyword data reads 0 until `SetKeywordData` stores a value, as `GetKeywordData` does.
    private static func installKeywordData(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 606, name: "GetKeywordDataForLocation", parameter1: .formID,
            parameter2: .formID
        ) { call in
            keywordData(call, index: 606, location: Self.parameterKey(call, call.parameter1))
        })
        // Parameter 1 is a location alias of the owning quest.
        registry.register(ConditionFunction(
            index: 608, name: "GetKeywordDataForAlias", parameter1: .integer, parameter2: .formID
        ) { call in
            let location = call.parameter1.flatMap(call.aliasLocation)
            return keywordData(call, index: 608, location: location.map(ReferenceKey.init))
        })
        registry.register(ConditionFunction(
            index: 651, name: "GetKeywordDataForCurrentLocation", parameter1: .formID
        ) { call in
            call.referenceKey().flatMap { reference in
                guard let current = call.context.data.currentLocation(of: reference) else {
                    return .failure(.unavailableData(.location))
                }
                return keywordData(
                    call, index: 651, location: ReferenceKey(resolved: current),
                    keyword: call.parameter1
                )
            }
        })
    }

    private static func keywordData(
        _ call: ConditionCall, index: UInt16, location: ReferenceKey?
    ) -> Result<Float, ConditionFailure> {
        keywordData(call, index: index, location: location, keyword: call.parameter2)
    }

    private static func keywordData(
        _ call: ConditionCall, index: UInt16, location: ReferenceKey?,
        keyword parameter: Condition.Parameter?
    ) -> Result<Float, ConditionFailure> {
        guard let location, let keyword = parameter.flatMap({ formKey(call, $0.asFormID) }) else {
            return .failure(.unresolvedParameter(index))
        }
        return Self.scriptState(call, of: location).map {
            $0.value(ScriptedStateName.keywordData(keyword)) ?? 0
        }
    }

    /// A keyword is a base record, never an alias fill, whatever the alias flag says.
    private static func formKey(_ call: ConditionCall, _ id: FormID) -> ReferenceKey? {
        if let target = call.context.formIDTranslation?.target {
            return ReferenceKey.resolve(id, using: target)
        }
        guard
            let plugin = call.context.data.sourcePlugin,
            let resolved = call.context.data.keywords?.resolvedID(id, fromPlugin: plugin)
        else { return nil }
        return ReferenceKey(resolved: resolved)
    }

    private static func scriptState(
        _ call: ConditionCall, of key: ReferenceKey
    ) -> Result<ScriptedReferenceState, ConditionFailure> {
        guard let state = call.context.scriptedState.state(of: key) else {
            return .failure(.unavailableData(.scriptState))
        }
        return .success(state)
    }
}
