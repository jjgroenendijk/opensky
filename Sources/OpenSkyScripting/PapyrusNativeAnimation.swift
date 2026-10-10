// Object animation natives. With an object behaviour graph, `PlayAnimation`
// raises a graph event and the waits end when the graph fires the named event.
// Without one they answer at once with a deviation, so latent chains run on.
// See docs/engine/object-animation.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

/// The object behaviour graphs of the running game. The app answers it.
@MainActor
public protocol PapyrusObjectAnimationBridge: AnyObject {
    /// Raises `event` on the object's graph. False when the object runs no graph.
    func playAnimation(_ event: String, on reference: ReferenceKey) -> Bool
    /// A token the app answers through `PapyrusScheduler.answer` when the graph
    /// fires `event`. Nil when the object runs no graph.
    func awaitAnimationEvent(_ event: String, on reference: ReferenceKey) -> UInt64?
}

extension PapyrusNativeFunctions {
    /// The wait without a graph: a trap loops on it while its cell is loaded, and an
    /// instant answer would spin that loop.
    static let animationEventWaitSeconds = 1.0

    public static func installDeferredAnimation(into registry: inout PapyrusNativeRegistry) {
        // `bool Function PlayAnimation(string asAnimation) native`
        animationNative("PlayAnimation", into: &registry) { call, bridge, key in
            guard let event = string(call, at: 0), bridge.playAnimation(event, on: key) else {
                return nil
            }
            return .returned(.boolean(true))
        }
        // `bool Function PlayAnimationAndWait(string asAnimation, string asEventName) native`
        animationNative("PlayAnimationAndWait", into: &registry) { call, bridge, key in
            guard
                let event = string(call, at: 0), let awaited = string(call, at: 1),
                bridge.playAnimation(event, on: key),
                let token = bridge.awaitAnimationEvent(awaited, on: key)
            else { return nil }
            return .suspended(.external(token))
        }
        // `bool Function WaitForAnimationEvent(string asEventName) native`
        animationNative("WaitForAnimationEvent", into: &registry) { call, bridge, key in
            guard
                let awaited = string(call, at: 0),
                let token = bridge.awaitAnimationEvent(awaited, on: key)
            else { return nil }
            return .suspended(.external(token))
        }
        registry.register(PapyrusNativeFunction(
            scriptName: "ObjectReference",
            functionName: "PlayGamebryoAnimation"
        ) { call, context in
            context.log.append("Deferred animation \(call.qualifiedName)")
            return .deviated(.boolean(true), .deferredAnimation)
        })
    }

    /// Registers a native that runs `body` when the receiver has a graph. A nil
    /// answer falls back: `WaitForAnimationEvent` is paced, the rest answer at once.
    private static func animationNative(
        _ functionName: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, any PapyrusObjectAnimationBridge, ReferenceKey
        ) -> PapyrusNativeResult?
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: "ObjectReference",
            functionName: functionName
        ) { call, context in
            if
                let world = context.world as? PapyrusWorldStateBridge,
                let bridge = world.objectAnimation,
                let receiver = call.receiver, let key = world.referenceKey(for: receiver),
                let result = body(call, bridge, key)
            {
                return result
            }
            if functionName == "WaitForAnimationEvent" {
                context.log.append("Paced \(call.qualifiedName)")
                return .suspended(.realSecondsAnswering(animationEventWaitSeconds, .boolean(true)))
            }
            context.log.append("Deferred animation \(call.qualifiedName)")
            return .deviated(.boolean(true), .deferredAnimation)
        })
    }
}
