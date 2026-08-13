// M18 location condition functions (issue #455), measured across the active
// load order before registration. All reads go through `ConditionDataResolution`.

import Foundation

nonisolated extension ConditionFunctions {
    static func installLocationData(_ registry: inout ConditionFunctionRegistry) {
        installDirectLocations(&registry)
        installLocationAliases(&registry)
        installSameLocation(&registry)
    }

    private static func installDirectLocations(
        _ registry: inout ConditionFunctionRegistry
    ) {
        // xEdit index 359, `GetInCurrentLoc`, parameter 1 `ptLocation`.
        // Returns 1 when the current location is the supplied location or a
        // child of it. (<https://ck.uesp.net/wiki/GetInCurrentLoc>)
        registry.register(locationParameterFunction(
            index: 359,
            name: "GetInCurrentLoc",
            answer: { store, current, parameter in
                Self.isTrue(store.isWithin(current, ancestor: parameter))
            }
        ))

        // xEdit index 565, `GetIsEditorLocation`, parameter 1 `ptLocation`.
        // Same containment rule as `GetIsEditorLocAlias`, with a Location
        // parameter. (<https://ck.uesp.net/wiki/GetIsEditorLocation>)
        registry.register(locationParameterFunction(
            index: 565,
            name: "GetIsEditorLocation",
            location: { call in Self.editorLocation(call) },
            answer: { store, editor, parameter in
                Self.isTrue(store.isWithin(editor, ancestor: parameter))
            }
        ))

        // xEdit index 444, `GetInCurrentLocFormList`, parameter 1 `ptFormList`.
        // Returns 1 when the current location or a parent is a location leaf in
        // the supplied list. (<https://ck.uesp.net/wiki/GetInCurrentLocFormList>)
        registry.register(ConditionFunction(
            index: 444,
            name: "GetInCurrentLocFormList",
            parameter1: .formID
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(444))
            }
            guard
                let lists = call.context.data.formLists,
                let sourcePlugin = call.context.data.sourcePlugin,
                let listID = lists.resolvedID(parameter.asFormID, fromPlugin: sourcePlugin),
                let flattened = lists.flattened(listID)
            else { return .failure(.unavailableData(.formList)) }
            return Self.currentLocation(call).flatMap { store, current in
                guard let answer = store.isWithinAny(current, locations: flattened.entries)
                else { return .failure(.unavailableData(.location)) }
                return .success(Self.isTrue(answer))
            }
        })

        // xEdit index 562, `LocationHasKeyword`, parameter 1 `ptKeyword`.
        // Returns 1 when the current location carries the keyword; OpenSky's
        // store follows the established parent inheritance rule.
        // (<https://ck.uesp.net/wiki/LocationHasKeyword>)
        registry.register(ConditionFunction(
            index: 562,
            name: "LocationHasKeyword",
            parameter1: .formID
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(562))
            }
            return Self.currentLocation(call).flatMap { store, current in
                guard
                    let sourcePlugin = call.context.data.sourcePlugin,
                    let keyword = store.keyword(
                        parameter.asFormID,
                        fromPlugin: sourcePlugin
                    )
                else { return .failure(.unavailableData(.keyword)) }
                return .success(Self.isTrue(store.hasKeyword(keyword, in: current)))
            }
        })
    }

    private static func installLocationAliases(
        _ registry: inout ConditionFunctionRegistry
    ) {
        // xEdit index 360, `GetInCurrentLocAlias`, parameter 1 `ptAlias`.
        // Returns 1 when current location is the filled location or its child.
        // (<https://ck.uesp.net/wiki/GetInCurrentLocAlias>)
        registry.register(locationAliasFunction(
            index: 360,
            name: "GetInCurrentLocAlias",
            answer: { store, current, alias in
                Self.isTrue(store.isWithin(current, ancestor: alias))
            }
        ))

        // xEdit index 567, `GetIsEditorLocAlias`, parameter 1 `ptAlias`.
        // Returns 1 when editor location is the filled location or its child.
        // (<https://ck.uesp.net/wiki/GetIsEditorLocAlias>)
        registry.register(locationAliasFunction(
            index: 567,
            name: "GetIsEditorLocAlias",
            location: { call in Self.editorLocation(call) },
            answer: { store, editor, alias in
                Self.isTrue(store.isWithin(editor, ancestor: alias))
            }
        ))

        // xEdit index 605, `LocAliasIsLocation`: parameter 1 `ptAlias`,
        // parameter 2 `ptLocation`. True only for the exact filled location.
        // (<https://ck.uesp.net/wiki/LocAliasIsLocation>)
        registry.register(ConditionFunction(
            index: 605,
            name: "LocAliasIsLocation",
            parameter1: .integer,
            parameter2: .formID
        ) { call in
            guard let aliasParameter = call.parameter1, let locationParameter = call.parameter2
            else { return .failure(.unresolvedParameter(605)) }
            guard
                let store = call.context.data.locations,
                let alias = call.aliasLocation(aliasParameter),
                store.location(alias) != nil,
                let sourcePlugin = call.context.data.sourcePlugin,
                let location = store.resolvedID(
                    locationParameter.asFormID,
                    fromPlugin: sourcePlugin
                ),
                store.location(location) != nil
            else { return .failure(.unavailableData(.location)) }
            return .success(Self.isTrue(alias == location))
        })

        // xEdit index 610, `LocAliasHasKeyword`: parameter 1 `ptAlias`,
        // parameter 2 `ptKeyword`. The CK page is empty; the name and typed
        // signature are the available contract, and parent inheritance is the
        // same `LocationStore` rule used by `LocationHasKeyword`.
        registry.register(ConditionFunction(
            index: 610,
            name: "LocAliasHasKeyword",
            parameter1: .integer,
            parameter2: .formID
        ) { call in
            guard let aliasParameter = call.parameter1, let keywordParameter = call.parameter2
            else { return .failure(.unresolvedParameter(610)) }
            guard
                let store = call.context.data.locations,
                let alias = call.aliasLocation(aliasParameter),
                store.location(alias) != nil,
                let sourcePlugin = call.context.data.sourcePlugin,
                let keyword = store.keyword(
                    keywordParameter.asFormID,
                    fromPlugin: sourcePlugin
                )
            else { return .failure(.unavailableData(.location)) }
            return .success(Self.isTrue(store.hasKeyword(keyword, in: alias)))
        })
    }
}
