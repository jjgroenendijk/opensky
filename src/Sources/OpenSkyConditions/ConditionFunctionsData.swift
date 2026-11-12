// Keyword and form-list condition functions. The location half is in
// `ConditionFunctions.ConditionFunctionsData.ConditionFunctionsDataLocations`. Indices are raw
// stored numbers from xEdit
// dev-4.1.6 Core/wbDefinitionsTES5.pas; Creation Kit numbers are 4096 higher.

import Foundation
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

nonisolated extension ConditionFunctions {
    nonisolated public enum ConditionFunctionsData {
        public static func installData(_ registry: inout ConditionFunctionRegistry) {
            installKeywordAndFormList(&registry)
            ConditionFunctions.ConditionFunctionsData.ConditionFunctionsDataLocations
                .installLocationData(&registry)
            ConditionFunctions.ConditionFunctionsData.ConditionFunctionsPlaces
                .installPlaces(&registry)
            ConditionFunctions.ConditionFunctionsData.ConditionFunctionsReferenceData
                .installReferenceData(&registry)
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
                if let form = call.formSubject() {
                    return ConditionFunctions.formHasKeyword(form, keyword: keyword, store: store)
                }
                return call.reference().flatMap { entry in
                    guard
                        let base = store.resolvedID(
                            ConditionFunctions.baseForm(of: entry),
                            fromPlugin: ConditionFunctions.ConditionFunctionsData
                                .basePlugin(of: entry.key)
                        ),
                        let answer = store.hasKeyword(keyword, on: base)
                    else { return .failure(.unavailableData(.keyword)) }
                    return .success(ConditionFunctions.isTrue(answer))
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
                if let form = call.formSubject() {
                    return .success(ConditionFunctions.isTrue(store.contains(form.id, in: listID)))
                }
                return call.reference().flatMap { entry in
                    guard
                        let base = store.resolvedID(
                            ConditionFunctions.baseForm(of: entry),
                            fromPlugin: ConditionFunctions.ConditionFunctionsData
                                .basePlugin(of: entry.key)
                        )
                    else { return .failure(.unavailableData(.formList)) }
                    return .success(ConditionFunctions.isTrue(store.contains(base, in: listID)))
                }
            })
        }
    }
}

nonisolated extension ConditionFunctions.ConditionFunctionsData {
    /// The plugin a reference's base FormID is spelled in. A reference made at run
    /// time names its base in load-order space.
    public static func basePlugin(of key: ReferenceKey) -> String {
        if case let .plugin(name, _) = key {
            return name
        }
        return FormIDResolver.loadOrderSpaceName
    }
}
