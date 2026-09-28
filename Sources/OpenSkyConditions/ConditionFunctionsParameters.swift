// Reference parameters, shared by every feature's condition functions.

import OpenSkyFormatsESM
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

    /// The same resolution for either parameter word, which is what
    /// `GetFactionRankDifference` needs: its actor is parameter #2 and its
    /// faction is parameter #1 (issue #508).
    public static func parameterReference(
        _ call: ConditionCall,
        _ parameter: Condition.Parameter?
    ) -> ReferenceKey? {
        guard let parameter else { return nil }
        if call.condition.flags.contains(.useAliases) {
            return call.aliasReference(parameter)
        }
        return call.context.references.entry(for: parameter.asFormID)?.key
    }
}
