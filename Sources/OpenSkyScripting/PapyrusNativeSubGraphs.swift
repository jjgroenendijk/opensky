// The sub-graph natives: the graphs of the art objects and armour addons on an actor.
// Both return nothing, so an actor without sub-graphs simply changes nothing
// (Creation Kit wiki, https://ck.uesp.net/wiki/Actor_Script).

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    static func installSubGraphNatives(into registry: inout PapyrusNativeRegistry) {
        // `Function PlaySubGraphAnimation(string asEventName) native`
        subGraphNative("PlaySubGraphAnimation", into: &registry) { call, bridge, actor in
            if let event = string(call, at: 0) {
                _ = bridge.playSubGraphAnimation(event, on: actor)
            }
        }
        // `Function SetSubGraphFloatVariable(string asVariableName, float afValue) native`
        subGraphNative("SetSubGraphFloatVariable", into: &registry) { call, bridge, actor in
            guard let name = string(call, at: 0), call.arguments.count > 1 else { return }
            let value: Float = switch call.arguments[1] {
            case let .float(real): real
            case let .integer(integer): Float(integer)
            default: 0
            }
            _ = bridge.setSubGraphFloatVariable(name, to: value, on: actor)
        }
    }

    /// Without the graphs, as in a headless session, the call is traced and does nothing.
    private static func subGraphNative(
        _ functionName: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, any PapyrusObjectAnimationBridge, ReferenceKey
        ) -> Void
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor", functionName: functionName
        ) { call, context in
            guard
                let world = context.world as? PapyrusWorldStateBridge,
                let bridge = world.objectAnimation,
                let key = call.receiver.flatMap(world.referenceKey(for:))
            else {
                context.log.append("Deferred animation \(call.qualifiedName)")
                return .deviated(.none, .deferredAnimation)
            }
            body(call, bridge, key)
            return .returned(.none)
        })
    }
}
