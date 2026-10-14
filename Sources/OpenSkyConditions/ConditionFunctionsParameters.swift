// Reference parameters, shared by every feature's condition functions.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

nonisolated extension ConditionFunctions {
    /// The reference parameter 1 names.
    ///
    /// Honours the `useAliases` flag exactly as `ConditionCall.parameter1`
    /// honours a CIS1 name override: with the flag set the word is a quest-alias
    /// index and the reference is whatever fills it, and without it the word is
    /// a FormID the runtime index resolves.
    public static func parameterReference(_ call: ConditionCall) -> ReferenceKey? {
        parameterReference(call, call.parameter1)
    }

    /// The same resolution for either parameter word. `GetFactionRankDifference`
    /// takes its faction from #1 and its actor from #2.
    public static func parameterReference(
        _ call: ConditionCall,
        _ parameter: Condition.Parameter?
    ) -> ReferenceKey? {
        guard let parameter else { return nil }
        if call.condition.flags.contains(.useAliases) {
            return call.aliasReference(parameter)
        }
        return call.referenceEntry(parameter.asFormID)?.key
    }
}

nonisolated extension ConditionFunctions {
    /// The reference a parameter names, even when it is not resident: an alias fill,
    /// an indexed placement, or the FormID resolved to its key. `PlayerRef` is `.player`.
    public static func parameterKey(
        _ call: ConditionCall,
        _ parameter: Condition.Parameter?
    ) -> ReferenceKey? {
        guard let parameter else { return nil }
        if call.condition.flags.contains(.useAliases) {
            return call.aliasReference(parameter)
        }
        let id = parameter.asFormID
        if let entry = call.referenceEntry(id) {
            return entry.key.namingPlayer
        }
        if
            let target = call.context.formIDTranslation?.target,
            let key = ReferenceKey.resolve(id, using: target)
        {
            return key.namingPlayer
        }
        guard
            let plugin = call.context.data.sourcePlugin,
            let resolved = call.context.data.keywords?.resolvedID(id, fromPlugin: plugin)
        else { return nil }
        return ReferenceKey(resolved: resolved).namingPlayer
    }
}
