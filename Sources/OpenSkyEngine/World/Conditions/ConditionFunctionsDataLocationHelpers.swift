// Shared location lookup and same-location functions for issue #455.

import Foundation

nonisolated extension ConditionFunctions {
    typealias ConditionLocationLookup = @Sendable (ConditionCall) -> Result<
        (LocationStore, ResolvedFormID), ConditionFailure
    >

    static func currentLocation(
        _ call: ConditionCall
    ) -> Result<(LocationStore, ResolvedFormID), ConditionFailure> {
        guard let store = call.context.data.locations else {
            return .failure(.unavailableData(.location))
        }
        return call.referenceKey().flatMap { reference in
            guard
                let location = call.context.data.currentLocation(of: reference),
                store.location(location) != nil
            else { return .failure(.unavailableData(.location)) }
            return .success((store, location))
        }
    }

    static func editorLocation(
        _ call: ConditionCall
    ) -> Result<(LocationStore, ResolvedFormID), ConditionFailure> {
        guard let store = call.context.data.locations else {
            return .failure(.unavailableData(.location))
        }
        return call.referenceKey().flatMap { reference in
            guard
                let location = call.context.data.editorLocation(of: reference),
                store.location(location) != nil
            else { return .failure(.unavailableData(.location)) }
            return .success((store, location))
        }
    }

    static func locationParameterFunction(
        index: UInt16,
        name: String,
        location: @escaping ConditionLocationLookup = { call in currentLocation(call) },
        answer: @escaping @Sendable (LocationStore, ResolvedFormID, ResolvedFormID) -> Float
    ) -> ConditionFunction {
        ConditionFunction(index: index, name: name, parameter1: .formID) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(index))
            }
            return location(call).flatMap { store, subject in
                guard
                    let sourcePlugin = call.context.data.sourcePlugin,
                    let wanted = store.resolvedID(
                        parameter.asFormID,
                        fromPlugin: sourcePlugin
                    ),
                    store.location(wanted) != nil
                else { return .failure(.unavailableData(.location)) }
                return .success(answer(store, subject, wanted))
            }
        }
    }

    static func locationAliasFunction(
        index: UInt16,
        name: String,
        location: @escaping ConditionLocationLookup = { call in currentLocation(call) },
        answer: @escaping @Sendable (LocationStore, ResolvedFormID, ResolvedFormID) -> Float
    ) -> ConditionFunction {
        ConditionFunction(index: index, name: name, parameter1: .integer) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(index))
            }
            return location(call).flatMap { store, subject in
                guard
                    let alias = call.aliasLocation(parameter),
                    store.location(alias) != nil
                else { return .failure(.unavailableData(.location)) }
                return .success(answer(store, subject, alias))
            }
        }
    }

    static func installSameLocation(_ registry: inout ConditionFunctionRegistry) {
        // xEdit indices 180 and 181: `HasSameEditorLocAsRef` takes a reference
        // and keyword, while `HasSameEditorLocAsRefAlias` takes a reference
        // alias and keyword. Both compare editor locations at the keyword's
        // parent level. (<https://ck.uesp.net/wiki/HasSameEditorLocAsRef>)
        registry.register(sameLocationFunction(
            index: 180,
            name: "HasSameEditorLocAsRef",
            location: { call in editorLocation(call) },
            other: { call, parameter in
                call.context.references.entry(for: parameter.asFormID)?.key
            }
        ))
        registry.register(sameLocationFunction(
            index: 181,
            name: "HasSameEditorLocAsRefAlias",
            location: { call in editorLocation(call) },
            other: { call, parameter in call.aliasReference(parameter) }
        ))

        // xEdit indices 603 and 604 are the current-location equivalents. A
        // null keyword compares immediate locations; otherwise the nearest
        // keyword-bearing ancestor defines the comparison level.
        // (<https://ck.uesp.net/wiki/IsInSameCurrentLocAsRef>)
        registry.register(sameLocationFunction(
            index: 603,
            name: "IsInSameCurrentLocAsRef",
            other: { call, parameter in
                call.context.references.entry(for: parameter.asFormID)?.key
            }
        ))
        registry.register(sameLocationFunction(
            index: 604,
            name: "IsInSameCurrentLocAsRefAlias",
            other: { call, parameter in call.aliasReference(parameter) }
        ))
    }

    private static func sameLocationFunction(
        index: UInt16,
        name: String,
        location: @escaping ConditionLocationLookup = { call in currentLocation(call) },
        other: @escaping @Sendable (ConditionCall, Condition.Parameter) -> ReferenceKey?
    ) -> ConditionFunction {
        ConditionFunction(
            index: index,
            name: name,
            parameter1: index == 180 || index == 603 ? .formID : .integer,
            parameter2: .formID
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(index))
            }
            guard let otherReference = other(call, parameter) else {
                return .failure(.unavailableData(.location))
            }
            return location(call).flatMap { store, subjectLocation in
                let otherLocation = index == 180 || index == 181
                    ? call.context.data.editorLocation(of: otherReference)
                    : call.context.data.currentLocation(of: otherReference)
                guard let otherLocation, store.location(otherLocation) != nil else {
                    return .failure(.unavailableData(.location))
                }
                return comparisonKeyword(call, store: store).flatMap { keyword in
                    guard
                        let answer = store.sharesLocation(
                            subjectLocation,
                            otherLocation,
                            at: keyword
                        ) else { return .failure(.unavailableData(.location)) }
                    return .success(Self.isTrue(answer))
                }
            }
        }
    }

    private static func comparisonKeyword(
        _ call: ConditionCall,
        store: LocationStore
    ) -> Result<ResolvedFormID?, ConditionFailure> {
        guard let parameter = call.parameter2 else {
            return .failure(.unresolvedParameter(call.condition.functionIndex))
        }
        guard !parameter.asFormID.isNull else { return .success(nil) }
        guard
            let sourcePlugin = call.context.data.sourcePlugin,
            let keyword = store.keyword(parameter.asFormID, fromPlugin: sourcePlugin)
        else { return .failure(.unavailableData(.keyword)) }
        return .success(keyword)
    }
}
