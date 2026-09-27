// The perk condition function (issue #497, roadmap item 20.4), split out of
// `ConditionFunctions` the way the actor, data and magic families are.
//
// One function, because the condition-function table carries one:
//
//   (Index: 448; Name: 'HasPerk'; ParamType1: ptPerk; ParamType2: ptInteger)
//
// from xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas. The index is the raw stored
// number; the Creation Kit spells it 4544.
//
// It is not an optional extra for the perk runtime — it is what makes a rank
// chain work. `Armsman00`'s perk-owner condition tab is `HasPerk Armsman20 == 0`
// on this machine's install, which is how a perk turns itself off once the
// actor takes the next rank of the same chain. Without this function every rank
// of every vanilla chain would stack.
//
// The second parameter is declared `ptInteger` by xEdit and is unused by every
// vanilla condition read here; nothing reads it, and a record that sets it is
// answered on the perk alone rather than refused.
//
// Documented in docs/formats/conditions.md and docs/engine/perks.md.

import Foundation

nonisolated extension ConditionFunctions {
    static func installPerk(_ registry: inout ConditionFunctionRegistry) {
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
