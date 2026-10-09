// The actor AI natives the opening cart ride uses: package re-evaluation,
// vehicles, idles, and animation events. The app answers them through
// `PapyrusActorAIBridge`; without it each one is a tallied failure.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkyWorldInterface

/// What the actor AI natives reach. The app answers it.
@MainActor
public protocol PapyrusActorAIBridge: AnyObject {
    func evaluatePackage(_ actor: ReferenceKey)
    /// Nil `vehicle` takes the rider off its vehicle.
    func setVehicle(_ rider: ReferenceKey, vehicle: ReferenceKey?)
    func tether(_ vehicle: ReferenceKey, to horse: ReferenceKey)
    /// False when the actor cannot play the idle.
    func playIdle(_ idle: ResolvedFormID, on actor: ReferenceKey) -> Bool
    func setPlayerAIDriven(_ driven: Bool)
}

extension PapyrusNativeFunctions {
    public static func installVehicle(into registry: inout PapyrusNativeRegistry) {
        // A call on an `Actor` variable looks the native up under `Actor`.
        for script in ["ObjectReference", "Actor"] {
            registry.register(PapyrusNativeFunction(
                scriptName: script, functionName: "Is3DLoaded"
            ) { call, context in
                guard
                    let world = context.world as? PapyrusWorldStateBridge,
                    let receiver = call.receiver, let key = world.referenceKey(for: receiver)
                else { return needsWorld(call) }
                let loaded = key == .player || world.references?.referenceEntry(key: key) != nil
                return .returned(.boolean(loaded))
            })
        }
        installAnimationEvents(into: &registry)
        installActorAI(into: &registry)
        for name in ["SetHudCartMode", "SetSittingRotation"] {
            registry.register(PapyrusNativeFunction(
                scriptName: "Game", functionName: name
            ) { call, context in
                context.log.append("Stubbed \(call.qualifiedName)")
                return .deviated(.none, .stubbed)
            })
        }
    }

    private static func installAnimationEvents(into registry: inout PapyrusNativeRegistry) {
        // `Alias` declares its own copy, which a rider alias such as `MQ101CartRiderScript` calls.
        for script in ["Form", "Alias"] {
            for name in ["RegisterForAnimationEvent", "UnregisterForAnimationEvent"] {
                installAnimationEvent(name, on: script, into: &registry)
            }
        }
    }

    private static func installAnimationEvent(
        _ name: String, on script: String, into registry: inout PapyrusNativeRegistry
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: script, functionName: name
        ) { call, context in
            guard
                let world = context.world as? PapyrusWorldStateBridge,
                let runtime = world.world, let receiver = call.receiver,
                let senderHandle = objectArgument(call, at: 0),
                let sender = world.referenceKey(for: senderHandle),
                let event = string(call, at: 1)
            else { return failure(call, "\(name) needs a sender and an event name") }
            guard name == "RegisterForAnimationEvent" else {
                runtime.unregisterAnimationEvent(handle: receiver, sender: sender, name: event)
                return .returned(.none)
            }
            let registered = runtime.registerAnimationEvent(
                handle: receiver, sender: sender, name: event
            )
            return .returned(.boolean(registered))
        })
    }

    private static func installActorAI(into registry: inout PapyrusNativeRegistry) {
        withActorAI("Actor", "EvaluatePackage", into: &registry) { _, _, ai, actor in
            ai.evaluatePackage(actor)
            return .returned(.none)
        }
        withActorAI("Actor", "SetVehicle", into: &registry) { call, world, ai, rider in
            let vehicle = objectArgument(call, at: 0).flatMap { world.referenceKey(for: $0) }
            ai.setVehicle(rider, vehicle: vehicle)
            return .returned(.none)
        }
        withActorAI("ObjectReference", "TetherToHorse", into: &registry) { call, world, ai, cart in
            guard
                let handle = objectArgument(call, at: 0),
                let horse = world.referenceKey(for: handle)
            else { return failure(call, "TetherToHorse needs a horse") }
            ai.tether(cart, to: horse)
            return .returned(.none)
        }
        withActorAI("Actor", "PlayIdle", into: &registry) { call, world, ai, actor in
            guard
                let handle = objectArgument(call, at: 0),
                case let .plugin(plugin, objectID)? = world.referenceKey(for: handle)
            else { return failure(call, "PlayIdle needs an idle") }
            let idle = ResolvedFormID(plugin: plugin, objectID: objectID)
            return .returned(.boolean(ai.playIdle(idle, on: actor)))
        }
        registry.register(PapyrusNativeFunction(
            scriptName: "Game", functionName: "SetPlayerAIDriven"
        ) { call, context in
            guard let ai = (context.world as? PapyrusWorldStateBridge)?.actorAI else {
                return failure(call, "SetPlayerAIDriven needs the actor AI bridge")
            }
            ai.setPlayerAIDriven(boolean(call, at: 0, default: true))
            return .returned(.none)
        })
    }

    private static func withActorAI(
        _ script: String, _ name: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, PapyrusWorldStateBridge, any PapyrusActorAIBridge, ReferenceKey
        ) -> PapyrusNativeResult
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: script, functionName: name
        ) { call, context in
            guard
                let world = context.world as? PapyrusWorldStateBridge, let ai = world.actorAI,
                let receiver = call.receiver, let key = world.referenceKey(for: receiver)
            else { return failure(call, "\(name) needs the actor AI bridge and a reference") }
            return body(call, world, ai, key)
        })
    }
}
