// Place condition functions, indices from xEdit wbDefinitionsTES5.pas: 84 GetDeadCount,
// 117 IsPlayerInRegion, 491 GetMapMarkerVisible, 563 LocationHasRefType, 592
// GetRefTypeAliveCount, 601 GetLocAliasRefTypeAliveCount, 625 IsLocationLoaded.
// See docs/engine/condition-functions-world.md#locations.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

/// Who died, where the player stands, and which map markers show.
nonisolated public struct PlaceConditionResolution: ConditionResolution, Sendable {
    public static let empty = PlaceConditionResolution()

    /// Nil without a world state to read deaths from.
    public let deadReferences: Set<ReferenceKey>?
    /// Dead placed actors per NPC_ base, raw FormIDs as the plugin spells them.
    public let deadCounts: [FormID: Int]
    /// The REGN records over the player's exterior cell, raw FormIDs.
    public let playerRegions: Set<FormID>?
    public let visibleMarkers: Set<ReferenceKey>?

    public init(
        deadReferences: Set<ReferenceKey>? = nil,
        deadCounts: [FormID: Int] = [:],
        playerRegions: Set<FormID>? = nil,
        visibleMarkers: Set<ReferenceKey>? = nil
    ) {
        self.deadReferences = deadReferences
        self.deadCounts = deadCounts
        self.playerRegions = playerRegions
        self.visibleMarkers = visibleMarkers
    }
}

nonisolated extension ConditionContext {
    public var places: PlaceConditionResolution {
        get { self[resolution: PlaceConditionResolution.self] }
        set { self[resolution: PlaceConditionResolution.self] = newValue }
    }
}

nonisolated extension ConditionFunctions {
    public static func installPlaces(_ registry: inout ConditionFunctionRegistry) {
        registry
            .register(ConditionFunction(
                index: 84,
                name: "GetDeadCount",
                parameter1: .formID
            ) { call in
                guard let base = call.parameter1?.asFormID
                else { return .failure(.unresolvedParameter(84)) }
                guard call.context.places.deadReferences != nil
                else { return .failure(.unavailableActorState) }
                return .success(Float(call.context.places.deadCounts[base] ?? 0))
            })
        registry.register(ConditionFunction(
            index: 117,
            name: "IsPlayerInRegion",
            parameter1: .formID
        ) { call in
            guard let regions = call.context.places.playerRegions else {
                return .failure(.unavailableData(.cell))
            }
            return .success(Self
                .isTrue(call.parameter1.map { regions.contains($0.asFormID) } ?? false))
        })
        registry.register(ConditionFunction(index: 491, name: "GetMapMarkerVisible") { call in
            call.referenceKey().flatMap { key in
                guard let markers = call.context.places.visibleMarkers else {
                    return .failure(.unavailableData(.reference))
                }
                return .success(Self.isTrue(markers.contains(key)))
            }
        })
        registry.register(ConditionFunction(
            index: 625,
            name: "IsLocationLoaded",
            parameter1: .formID
        ) { call in
            locationParameter(call, call.parameter1) { store, location in
                let current = call.context.data.currentLocation(of: .player)
                return Self.isTrue(current.map { store.isWithin($0, ancestor: location) } ?? false)
            }
        })
        installRefTypes(&registry)
    }

    private static func installRefTypes(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 563, name: "LocationHasRefType", parameter1: .formID
        ) { call in
            call.referenceKey().flatMap { key in
                guard let current = call.context.data.currentLocation(of: key) else {
                    return .failure(.unavailableData(.location))
                }
                return refTypeCount(call, type: call.parameter1, in: current, aliveOnly: false)
                    .map { Self.isTrue($0 > 0) }
            }
        })
        registry.register(ConditionFunction(
            index: 592, name: "GetRefTypeAliveCount", parameter1: .formID, parameter2: .formID
        ) { call in
            guard
                let store = call.context.data.locations,
                let plugin = call.context.data.sourcePlugin,
                let location = call.parameter1.flatMap({ store.resolvedID(
                    $0.asFormID,
                    fromPlugin: plugin
                ) })
            else { return .failure(.unavailableData(.location)) }
            return refTypeCount(call, type: call.parameter2, in: location, aliveOnly: true)
        })
        registry.register(ConditionFunction(
            index: 601, name: "GetLocAliasRefTypeAliveCount", parameter1: .integer,
            parameter2: .formID
        ) { call in
            guard let location = call.parameter1.flatMap({ call.aliasLocation($0) }) else {
                return .failure(.unavailableData(.location))
            }
            return refTypeCount(call, type: call.parameter2, in: location, aliveOnly: true)
        })
    }

    /// How many references `location` lists under the `LCRT` parameter, the dead left
    /// out when `aliveOnly`.
    private static func refTypeCount(
        _ call: ConditionCall,
        type parameter: Condition.Parameter?,
        in location: ResolvedFormID,
        aliveOnly: Bool
    ) -> Result<Float, ConditionFailure> {
        guard
            let store = call.context.data.locations,
            let plugin = call.context.data.sourcePlugin,
            let type = parameter.flatMap({ store.resolvedID($0.asFormID, fromPlugin: plugin) })
        else { return .failure(.unavailableData(.location)) }
        let dead = call.context.places.deadReferences ?? []
        let listed = store.specialReferences(ofType: ReferenceKey(resolved: type), in: location)
        return .success(Float(listed.count { !aliveOnly || !dead.contains($0) }))
    }

    private static func locationParameter(
        _ call: ConditionCall,
        _ parameter: Condition.Parameter?,
        read: (LocationStore, ResolvedFormID) -> Float
    ) -> Result<Float, ConditionFailure> {
        guard
            let store = call.context.data.locations,
            let plugin = call.context.data.sourcePlugin,
            let location = parameter.flatMap({ store.resolvedID($0.asFormID, fromPlugin: plugin) }),
            store.location(location) != nil
        else { return .failure(.unavailableData(.location)) }
        return .success(read(store, location))
    }
}
