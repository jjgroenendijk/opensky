// M18 keyword and form-list condition functions (issue #455). The location
// half is in `ConditionFunctionsDataLocations` to keep both files reviewable.
//
// Indices are raw stored numbers from xEdit dev-4.1.6
// Core/wbDefinitionsTES5.pas. Creation Kit numbers are 4096 higher.

import Foundation

nonisolated extension ConditionFunctions {
    static func installData(_ registry: inout ConditionFunctionRegistry) {
        installKeywordAndFormList(&registry)
        installLocationData(&registry)
    }

    private static func installKeywordAndFormList(
        _ registry: inout ConditionFunctionRegistry
    ) {
        // xEdit index 560, `HasKeyword`, parameter 1 `ptKeyword`.
        // "Returns 1 if the calling ref's base object has the specified
        // keyword." (<https://ck.uesp.net/wiki/HasKeyword>)
        registry.register(ConditionFunction(
            index: 560,
            name: "HasKeyword",
            parameter1: .formID
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(560))
            }
            guard
                let store = call.context.data.keywords,
                let sourcePlugin = call.context.data.sourcePlugin,
                let keyword = store.resolvedID(parameter.asFormID, fromPlugin: sourcePlugin),
                store.keyword(keyword) != nil
            else { return .failure(.unavailableData(.keyword)) }
            return call.reference().flatMap { entry in
                guard
                    case let .plugin(pluginName, _) = entry.key,
                    let base = store.resolvedID(
                        Self.baseForm(of: entry),
                        fromPlugin: pluginName
                    ),
                    let answer = store.hasKeyword(keyword, on: base)
                else { return .failure(.unavailableData(.keyword)) }
                return .success(Self.isTrue(answer))
            }
        })

        // xEdit index 372, `IsInList`, parameter 1 `ptFormList`.
        // Returns 1 when the reference's base object is a member of the list.
        // (<https://ck.uesp.net/wiki/IsInList>) Nested lists are flattened by
        // `FormListStore`, so membership has the same semantics at every depth.
        registry.register(ConditionFunction(
            index: 372,
            name: "IsInList",
            parameter1: .formID
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(372))
            }
            guard
                let store = call.context.data.formLists,
                let sourcePlugin = call.context.data.sourcePlugin,
                let listID = store.resolvedID(parameter.asFormID, fromPlugin: sourcePlugin),
                store.formList(listID) != nil
            else { return .failure(.unavailableData(.formList)) }
            return call.reference().flatMap { entry in
                guard
                    case let .plugin(pluginName, _) = entry.key,
                    let base = store.resolvedID(
                        Self.baseForm(of: entry),
                        fromPlugin: pluginName
                    )
                else { return .failure(.unavailableData(.formList)) }
                return .success(Self.isTrue(store.contains(base, in: listID)))
            }
        })
    }
}
