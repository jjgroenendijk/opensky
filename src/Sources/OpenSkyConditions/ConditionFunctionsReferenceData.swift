// Condition functions that read a placement record: identity, linked references,
// and location ref types. Linked references come from `XLKR` as the plugin wrote
// them. See docs/engine/condition-functions.md#references.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

nonisolated extension ConditionFunctions {
    public static func installReferenceData(_ registry: inout ConditionFunctionRegistry) {
        // "Returns 1 if the calling object is the specified reference."
        // (<https://ck.uesp.net/wiki/GetIsReference>)
        registry.register(ConditionFunction(
            index: 136, name: "GetIsReference", parameter1: .formID
        ) { call in
            guard let parameter = Self.parameterKey(call, call.parameter1) else {
                return .failure(.unresolvedParameter(136))
            }
            return call.referenceKey().map { Self.isTrue($0.namingPlayer == parameter) }
        })

        // "Returns 1 if the calling object is an Actor." (<https://ck.uesp.net/wiki/IsActor>)
        registry.register(ConditionFunction(index: 353, name: "IsActor") { call in
            call.referenceKey().flatMap { key in
                if key.namingPlayer == .player {
                    return .success(1)
                }
                guard let entry = call.context.references[key] else {
                    return .failure(.unresolvedReference(call.condition.runOn))
                }
                return .success(Self.isTrue(entry.placedActor != nil))
            }
        })

        installLinkedReferences(&registry)
        installObjectType(&registry)

        // "HasRefType returns 1 if the calling ref has been flagged as being the
        // specified location ref type." (<https://ck.uesp.net/wiki/HasRefType>)
        registry.register(ConditionFunction(
            index: 561, name: "HasRefType", parameter1: .formID
        ) { call in
            guard let type = Self.recordKey(call, call.parameter1) else {
                return .failure(.unresolvedParameter(561))
            }
            return call.reference().flatMap { entry in
                Self.refTypes(of: entry, call).map { Self.isTrue($0.contains(type)) }
            }
        })
    }

    private static func installLinkedReferences(_ registry: inout ConditionFunctionRegistry) {
        // xEdit: parameter 1 `ptKeyword`. A null keyword asks for the untagged link.
        registry.register(ConditionFunction(
            index: 362, name: "HasLinkedRef", parameter1: .formID
        ) { call in
            let keyword = Self.optionalRecordKey(call, call.parameter1)
            guard case let .some(keyword) = keyword else {
                return .failure(.unresolvedParameter(362))
            }
            return call.reference().flatMap { entry in
                Self.linkedReferences(of: entry, keyword: keyword, call)
                    .map { Self.isTrue(!$0.isEmpty) }
            }
        })

        // xEdit: parameter 1 `ptReference`, parameter 2 `ptKeyword`. 1 when the run-on
        // reference links to the parameter under that keyword.
        registry.register(ConditionFunction(
            index: 650, name: "IsLinkedTo", parameter1: .formID, parameter2: .formID
        ) { call in
            guard
                let target = Self.parameterKey(call, call.parameter1),
                case let .some(keyword) = Self.optionalRecordKey(call, call.parameter2)
            else { return .failure(.unresolvedParameter(650)) }
            return call.reference().flatMap { entry in
                Self.linkedReferences(of: entry, keyword: keyword, call)
                    .map { Self.isTrue($0.contains(target)) }
            }
        })
    }

    /// A record parameter as a key in the stores' space; nil when it does not resolve.
    static func recordKey(
        _ call: ConditionCall,
        _ parameter: Condition.Parameter?
    ) -> ReferenceKey? {
        guard
            let parameter,
            let plugin = call.context.data.sourcePlugin,
            let resolved = call.context.data.keywords?
                .resolvedID(parameter.asFormID, fromPlugin: plugin)
        else { return nil }
        return ReferenceKey(resolved: resolved)
    }

    /// `.some(nil)` for the null FormID, which means "no keyword".
    private static func optionalRecordKey(
        _ call: ConditionCall,
        _ parameter: Condition.Parameter?
    ) -> ReferenceKey?? {
        if parameter?.asFormID.isNull ?? true {
            return .some(nil)
        }
        return recordKey(call, parameter).map { .some($0) } ?? .none
    }

    /// The references `entry` links to under `keyword`, as keys.
    private static func linkedReferences(
        of entry: RuntimeReferenceEntry,
        keyword: ReferenceKey?,
        _ call: ConditionCall
    ) -> Result<[ReferenceKey], ConditionFailure> {
        guard let store = call.context.data.keywords else {
            return .failure(.unavailableData(.reference))
        }
        let plugin = basePlugin(of: entry.key)
        let key = { (id: FormID) in
            store.resolvedID(id, fromPlugin: plugin).map(ReferenceKey.init(resolved:))
        }
        let links = entry.placedReference?.linkedReferences
            ?? entry.placedActor?.details.linkedReferences ?? []
        return .success(links.compactMap { link in
            guard link.keyword.flatMap(key) == keyword else { return nil }
            return key(link.ref)?.namingPlayer
        })
    }

    /// `XLRT` on the placement, plus every location that lists it in `LCSR` or `ACSR`.
    private static func refTypes(
        of entry: RuntimeReferenceEntry,
        _ call: ConditionCall
    ) -> Result<Set<ReferenceKey>, ConditionFailure> {
        guard let store = call.context.data.keywords else {
            return .failure(.unavailableData(.reference))
        }
        let plugin = basePlugin(of: entry.key)
        let details = entry.placedReference?.details ?? entry.placedActor?.details
        var types = Set((details?.locationRefTypes ?? []).compactMap {
            store.resolvedID($0, fromPlugin: plugin).map(ReferenceKey.init(resolved:))
        })
        if let locations = call.context.data.locations {
            types.formUnion(locations.specialReferenceTypes(of: entry.key))
        }
        return .success(types)
    }
}
