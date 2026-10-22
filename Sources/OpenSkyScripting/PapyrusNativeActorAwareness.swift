// What an actor sees and runs: `HasLOS`, `IsDetectedBy`, `GetCurrentPackage`,
// `GetLightLevel`, `Package.GetTemplate`, and `ResetHealthAndLimbs`
// (<https://ck.uesp.net/wiki/Actor_Script>). A
// pair perception
// does not track is a failure, not a false. See docs/engine/papyrus-actor-natives.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPerceptionInterface
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    public static func installActorAwareness(into registry: inout PapyrusNativeRegistry) {
        // "Checks to see if this actor has line-of-sight to the target object."
        withDetectionPair("HasLOS", into: &registry) { actor, other, detection in
            detection.pair(observer: actor, target: other).map { .boolean($0.hasLineOfSight) }
        }
        // "Is this actor currently detected by the other one?"
        withDetectionPair("IsDetectedBy", into: &registry) { actor, other, detection in
            detection.pair(observer: other, target: actor).map { .boolean($0.isDetected) }
        }
        withActorBridge("GetCurrentPackage", into: &registry) { call, bridge, actor in
            guard let lookup = bridge.sessionNatives.currentPackage else {
                return failure(call, "GetCurrentPackage needs a package runtime")
            }
            let handle = lookup(actor)
                .flatMap(bridge.referenceKey(forFormID:))
                .flatMap(bridge.objectHandle(for:))
            return .returned(handle.map { .object($0) } ?? .none)
        }
        // Detection's light is this value over 100 (docs/engine/detection.md#light-level).
        withActorBridge("GetLightLevel", into: &registry) { call, bridge, actor in
            guard
                let light = bridge.perceptionNatives.lightLevel, let feet = position(
                    of: actor,
                    bridge
                )
            else {
                return failure(call, "GetLightLevel needs the renderer and the actor's position")
            }
            return .returned(.float(light(feet) * 100))
        }
        // The `PKCU` template package, or None for a package built without one.
        scriptState("Package", "GetTemplate", into: &registry) { call, bridge, key in
            guard
                case let .plugin(plugin, objectID) = key,
                let package = bridge.formIDResolver?.localFormID(
                    of: ResolvedFormID(plugin: plugin, objectID: objectID)
                ),
                let lookup = bridge.sessionNatives.packageTemplate
            else { return failure(call, "GetTemplate needs the package records") }
            return .returned(lookup(package).map { formHandle($0, in: bridge) } ?? .none)
        }
        // "Resets this actor's health and restores all his limbs." OpenSky has no limb
        // damage, so only health moves.
        withActorBridge("ResetHealthAndLimbs", into: &registry) { call, bridge, actor in
            guard
                let values = bridge.actorNatives.actorValueRuntime?(),
                let holder = bridge.actorHolder(for: actor)
            else { return failure(call, "ResetHealthAndLimbs needs actor values") }
            values.set(.health, to: values.maximums(of: holder)[.health], on: holder)
            return .returned(.none)
        }
    }

    private static func withActorBridge(
        _ name: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, PapyrusWorldStateBridge, ReferenceKey
        ) -> PapyrusNativeResult
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor", functionName: name
        ) { call, context in
            guard
                let bridge = context.world as? PapyrusWorldStateBridge,
                let receiver = call.receiver,
                let actor = bridge.referenceKey(for: receiver)
            else { return needsActor(call) }
            return body(call, bridge, actor)
        })
    }

    private static func withDetectionPair(
        _ name: String,
        into registry: inout PapyrusNativeRegistry,
        read: @escaping @MainActor (
            ReferenceKey, ReferenceKey, DetectionResolution
        ) -> PapyrusValue?
    ) {
        withActorBridge(name, into: &registry) { call, bridge, actor in
            guard
                let handle = objectArgument(call, at: 0),
                let other = bridge.referenceKey(for: handle)
            else { return failure(call, "\(name) needs a reference argument") }
            guard let detection = bridge.perceptionNatives.detection?() else {
                return failure(call, "\(name) needs a perception pass")
            }
            guard let answer = read(actor, other, detection) else {
                return failure(call, "\(name): perception tracks no such pair")
            }
            return .returned(answer)
        }
    }
}
