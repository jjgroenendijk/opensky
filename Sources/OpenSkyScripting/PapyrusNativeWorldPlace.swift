// Where a reference is: its location, cell, worldspace, distance, and heading
// (<https://ck.uesp.net/wiki/ObjectReference_Script>), `Location.IsChild`,
// `Utility.GetCurrentGameTime`, and `Game.GetFormFromFile`. The place reads use the
// snapshot conditions read, so a script and a condition agree on where a reference is.
//
// Documented in docs/engine/papyrus-activation.md, with the gaps against the game.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScriptingInterface
import OpenSkyWorldState
import simd

extension PapyrusNativeFunctions {
    /// The distance between references that do not share a worldspace or interior.
    /// The game's own value there is not documented; any range check fails on it.
    static let separateSpaceDistance = Float.greatestFiniteMagnitude

    public static func installWorldPlace(into registry: inout PapyrusNativeRegistry) {
        installPlaceReads(into: &registry)
        installDistanceReads(into: &registry)
        installLocationReads(into: &registry)
        installGameTimeAndForms(into: &registry)
    }

    /// `Location GetCurrentLocation()`, `Cell GetParentCell()`, and `WorldSpace
    /// GetWorldSpace()`. Each is None for a reference no resident cell holds, and the
    /// worldspace is None in an interior, as in the game.
    private static func installPlaceReads(into registry: inout PapyrusNativeRegistry) {
        withPlace("GetCurrentLocation", into: &registry) { target, data, world in
            data.currentLocation(of: target).flatMap { location in
                world.objectHandle(for: ReferenceKey(resolved: location))
            }
        }
        withPlace("GetParentCell", into: &registry) { target, data, world in
            data.cell(of: target).flatMap { place in
                world.referenceKey(forFormID: place.cell).flatMap(world.objectHandle(for:))
            }
        }
        withPlace("GetWorldSpace", into: &registry) { target, data, world in
            data.cell(of: target)?.worldspace.flatMap { worldspace in
                world.referenceKey(forFormID: worldspace).flatMap(world.objectHandle(for:))
            }
        }
    }

    /// `float GetDistance(ObjectReference akOther)`, `float GetHeadingAngle(ObjectReference
    /// akOther)`, and `float GetScale()`. The heading is in degrees from -180 to 180,
    /// positive when the other reference is clockwise from where this one faces.
    private static func installDistanceReads(into registry: inout PapyrusNativeRegistry) {
        withOther("GetDistance", into: &registry) { call, world, key, other in
            guard let start = position(of: key, world), let end = position(of: other, world) else {
                return needsResidentReference(call)
            }
            guard sharesSpace(key, other, world) else {
                return .returned(.float(separateSpaceDistance))
            }
            return .returned(.float(simd_distance(start, end)))
        }
        withOther("GetHeadingAngle", into: &registry) { call, world, key, other in
            guard
                let state = world.referenceState(for: key),
                let start = position(of: key, world),
                let end = position(of: other, world)
            else { return needsResidentReference(call) }
            let bearing = atan2(end.x - start.x, end.y - start.y)
            return .returned(.float(degreesFromMinus180(bearing - state.transform.rotation.z)))
        }
        registry.register(PapyrusNativeFunction(
            scriptName: "ObjectReference", functionName: "GetScale"
        ) { call, context in
            guard let target = worldTarget(call, context) else { return needsWorld(call) }
            guard let state = target.world.referenceState(for: target.key) else {
                return needsResidentReference(call)
            }
            return .returned(.float(state.transform.scale))
        })
    }

    /// `bool IsChild(Location akOther)`: whether `akOther` sits below this location in the
    /// `PNAM` parent chain. A location is not its own child.
    private static func installLocationReads(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Location", functionName: "IsChild"
        ) { call, context in
            guard
                let target = worldTarget(call, context),
                let bridge = context.world as? PapyrusWorldStateBridge,
                let store = bridge.conditionData?().locations
            else { return failure(call, "IsChild needs location data and a location") }
            guard
                let handle = objectArgument(call, at: 0),
                let other = target.world.referenceKey(for: handle),
                case let .plugin(parentPlugin, parentObject) = target.key,
                case let .plugin(childPlugin, childObject) = other
            else { return .returned(.boolean(false)) }
            let parent = ResolvedFormID(plugin: parentPlugin, objectID: parentObject)
            let child = ResolvedFormID(plugin: childPlugin, objectID: childObject)
            guard other != target.key, store.location(child) != nil else {
                return .returned(.boolean(false))
            }
            return .returned(.boolean(store.isWithin(child, ancestor: parent)))
        })
    }

    /// `float Utility.GetCurrentGameTime()`, the days passed as `GameDaysPassed` holds
    /// them, and `Form Game.GetFormFromFile(int aiFormID, string asFilename)`.
    private static func installGameTimeAndForms(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Utility", functionName: "GetCurrentGameTime"
        ) { call, context in
            guard
                let bridge = context.world as? PapyrusWorldStateBridge,
                let clock = bridge.clockSource?()
            else { return failure(call, "GetCurrentGameTime needs a game clock") }
            return .returned(.float(clock.daysPassed))
        })
        registry.register(PapyrusNativeFunction(
            scriptName: "Game", functionName: "GetFormFromFile"
        ) { call, context in
            guard
                let bridge = context.world as? PapyrusWorldStateBridge,
                let loadOrder = bridge.formIDResolver
            else { return failure(call, "GetFormFromFile needs the load order") }
            guard let raw = integer(call, at: 0), let file = string(call, at: 1) else {
                return failure(call, "GetFormFromFile needs a FormID and a file name")
            }
            let form = ResolvedFormID(plugin: file, objectID: UInt32(bitPattern: raw) & 0xFFFFFF)
            // A file outside the load order has no forms, which is how mods test for a DLC.
            guard loadOrder.localFormID(of: form) != nil else { return .returned(.none) }
            let key = ReferenceKey(resolved: form)
            return .returned(bridge.objectHandle(for: key).map { .object($0) } ?? .none)
        })
    }

    private static func position(
        of key: ReferenceKey, _ world: PapyrusWorldStateBridge
    ) -> SIMD3<Float>? {
        world.livePosition?(key) ?? world.referenceState(for: key)?.transform.position
    }

    /// True unless both cells are known and lie in different worldspaces or interiors.
    private static func sharesSpace(
        _ first: ReferenceKey, _ second: ReferenceKey, _ world: PapyrusWorldStateBridge
    ) -> Bool {
        guard
            let data = world.conditionData?(),
            let left = data.cell(of: first),
            let right = data.cell(of: second)
        else { return true }
        return left.worldspace == right.worldspace
            && (left.worldspace != nil || left.cell == right.cell)
    }

    private static func degreesFromMinus180(_ radians: Float) -> Float {
        var degrees = (radians * 180 / .pi).truncatingRemainder(dividingBy: 360)
        if degrees > 180 {
            degrees -= 360
        } else if degrees < -180 {
            degrees += 360
        }
        return degrees
    }

    /// Registers an `ObjectReference` read of the receiver's place snapshot.
    private static func withPlace(
        _ name: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            ReferenceKey, ConditionDataResolution, PapyrusWorldStateBridge
        ) -> PapyrusObjectHandle?
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: "ObjectReference", functionName: name
        ) { call, context in
            guard
                let bridge = context.world as? PapyrusWorldStateBridge,
                let data = bridge.conditionData?(),
                let receiver = call.receiver,
                let key = bridge.referenceKey(for: receiver)
            else { return failure(call, "\(name) needs place data and a reference") }
            return .returned(body(key, data, bridge).map { .object($0) } ?? .none)
        })
    }

    /// Registers an `ObjectReference` native whose argument 0 is another reference.
    private static func withOther(
        _ name: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, PapyrusWorldStateBridge, ReferenceKey, ReferenceKey
        ) -> PapyrusNativeResult
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: "ObjectReference", functionName: name
        ) { call, context in
            guard
                let bridge = context.world as? PapyrusWorldStateBridge,
                let receiver = call.receiver,
                let key = bridge.referenceKey(for: receiver)
            else { return needsWorld(call) }
            guard
                let handle = objectArgument(call, at: 0),
                let other = bridge.referenceKey(for: handle)
            else { return failure(call, "\(name) needs another reference") }
            return body(call, bridge, key, other)
        })
    }
}
