// `Game.FindClosest*` and `Game.FindRandom*` (Creation Kit wiki "FindClosestReferenceOfType
// - Game"): enabled resident references within a radius of a point. The player counts as
// an actor, as the wiki notes for `FindClosestActor`.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension PapyrusNativeFunctions {
    private enum FindFilter {
        case actors, baseForm, baseFormList
    }

    static func installFindReferences(into registry: inout PapyrusNativeRegistry) {
        let filters: [(String, FindFilter)] = [
            ("Actor", .actors),
            ("ReferenceOfType", .baseForm),
            ("ReferenceOfAnyTypeInList", .baseFormList)
        ]
        for (suffix, filter) in filters {
            for closest in [true, false] {
                let name = (closest ? "FindClosest" : "FindRandom") + suffix
                registry.register(PapyrusNativeFunction(
                    scriptName: "Game", functionName: name
                ) { call, context in
                    guard let bridge = context.world as? PapyrusWorldStateBridge else {
                        return needsWorld(call)
                    }
                    let first = filter == .actors ? 0 : 1
                    guard
                        let x = float(call, at: first), let y = float(call, at: first + 1),
                        let z = float(call, at: first + 2), let radius = float(call, at: first + 3)
                    else { return failure(call, "\(name) needs a point and a radius") }
                    guard let bases = findBases(call, filter, bridge) else {
                        return failure(call, "\(name) needs a base form")
                    }
                    let found = findCandidates(
                        bridge, filter: filter, bases: bases, around: SIMD3(x, y, z),
                        radius: radius
                    )
                    let pick = closest
                        ? found.min { ($0.distance, $0.key) < ($1.distance, $1.key) }
                        : found
                        .isEmpty ? nil : found[Int(context.random.next() % UInt64(found.count))]
                    return .returned(pick.flatMap { bridge.objectHandle(for: $0.key) }.map {
                        .object($0)
                    } ?? .none)
                })
            }
        }
    }

    /// The base forms a reference must have; empty for the actor search.
    private static func findBases(
        _ call: PapyrusNativeCall, _ filter: FindFilter, _ bridge: PapyrusWorldStateBridge
    ) -> Set<ReferenceKey>? {
        if filter == .actors {
            return []
        }
        guard let form = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:)) else {
            return nil
        }
        guard filter == .baseFormList else { return [form] }
        return bridge.pluginFormListEntries(of: form).map { Set($0.compactMap(\.self)) }
    }

    private static func findCandidates(
        _ bridge: PapyrusWorldStateBridge, filter: FindFilter, bases: Set<ReferenceKey>,
        around centre: SIMD3<Float>, radius: Float
    ) -> [(key: ReferenceKey, distance: Float)] {
        let entries = bridge.references?.residentEntries() ?? []
        var keys = entries.compactMap { entry -> ReferenceKey? in
            switch filter {
            case .actors:
                entry.placedActor == nil ? nil : entry.key
            case .baseForm, .baseFormList:
                bridge.resolvedBase(of: entry.key).flatMap { bases.contains($0) ? entry.key : nil }
            }
        }
        if filter == .actors {
            keys.append(.player)
        }
        return keys.compactMap { key in
            if
                let state = bridge.referenceState(for: key),
                !state.enableState.isEnabled || state.deletion.isDeleted
            {
                return nil
            }
            guard let position = position(of: key, bridge) else { return nil }
            let distance = simd_distance(position, centre)
            return distance <= radius ? (key, distance) : nil
        }
    }
}
