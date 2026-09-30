// The perk condition function: 448 `HasPerk` (ptPerk, ptInteger), from xEdit
// dev-4.1.6 Core/wbDefinitionsTES5.pas. Rank chains need it: `Armsman00` turns
// itself off with `HasPerk Armsman20 == 0`. The integer parameter is unused.
// See docs/engine/condition-functions.md and docs/engine/perks.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM

nonisolated extension ConditionFunctions {
    public static func installPerk(_ registry: inout ConditionFunctionRegistry) {
        // "Returns whether the actor has the specified perk."
        // (<https://ck.uesp.net/wiki/HasPerk>) The run-on names the actor, and
        // parameter 1 names the PERK record.
        registry.register(ConditionFunction(
            index: 448,
            name: "HasPerk",
            parameter1: .formID,
            parameter2: .integer
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(448))
            }
            guard let perk = call.context.perks.key(of: parameter.asFormID) else {
                return .failure(.unavailablePerks)
            }
            return call.referenceKey().flatMap { actor in
                guard let owns = call.context.perks.owns(perk, on: actor) else {
                    return .failure(.unavailablePerks)
                }
                return .success(Self.isTrue(owns))
            }
        })
    }
}
