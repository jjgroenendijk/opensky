// The argument reads and failure results every native family shares. The owner and
// each family adopt the protocol, so a call reads `failure(call, ...)` unqualified.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkyWorldState

protocol PapyrusNativeArguments {}

extension PapyrusNativeArguments {
    /// The world façade plus the world identity of `self`, for an `Actor`
    /// method. Identical in shape to `worldTarget(_:_:)`; named separately so
    /// the failure it produces can say "actor" rather than "reference".
    static func actorTarget(
        _ call: PapyrusNativeCall,
        _ context: PapyrusNativeContext
    ) -> (world: any PapyrusWorldBridge, key: ReferenceKey)? {
        worldTarget(call, context)
    }

    /// The single failure an `Actor` native returns when it has no world, no
    /// world identity for its receiver, or no actor behind that identity.
    static func needsActor(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
        failure(call, "\(call.functionName) needs a world runtime and an actor receiver")
    }

    /// Argument `index` as an object handle, or nil for a missing argument and
    /// for Papyrus `None` alike — which `Kill(akKiller = None)` relies on.
    static func objectArgument(_ call: PapyrusNativeCall, at index: Int) -> PapyrusObjectHandle? {
        guard
            call.arguments.indices.contains(index),
            case let .object(handle) = call.arguments[index] else { return nil }
        return handle
    }

    static func failure(_ call: PapyrusNativeCall, _ detail: String) -> PapyrusNativeResult {
        .failed(.invalidArguments(function: call.qualifiedName, detail: detail))
    }

    static func float(_ call: PapyrusNativeCall, at index: Int) -> Float? {
        guard call.arguments.indices.contains(index) else { return nil }
        return switch call.arguments[index] {
        case let .float(value):
            value
        case let .integer(value):
            Float(value)
        default:
            nil
        }
    }

    static func integer(_ call: PapyrusNativeCall, at index: Int) -> Int32? {
        guard
            call.arguments.indices.contains(index),
            case let .integer(value) = call.arguments[index] else { return nil }
        return value
    }

    /// An optional Bool argument, `fallback` when the call left it off. An
    /// integer reads as its truth value, which is what the compiler's implicit
    /// cast of an int literal produces.
    static func boolean(_ call: PapyrusNativeCall, at index: Int, default fallback: Bool) -> Bool {
        guard call.arguments.indices.contains(index) else { return fallback }
        return switch call.arguments[index] {
        case let .boolean(value): value
        case let .integer(value): value != 0
        default: fallback
        }
    }

    static func string(_ call: PapyrusNativeCall, at index: Int) -> String? {
        guard
            call.arguments.indices.contains(index),
            case let .string(value) = call.arguments[index] else { return nil }
        return value
    }

    /// The world façade plus the world identity of `self`, or nil when either
    /// is missing. Every world-touching native starts with this.
    static func worldTarget(
        _ call: PapyrusNativeCall,
        _ context: PapyrusNativeContext
    ) -> (world: any PapyrusWorldBridge, key: ReferenceKey)? {
        guard
            let world = context.world,
            let receiver = call.receiver,
            let key = world.referenceKey(for: receiver)
        else { return nil }
        return (world, key)
    }

    /// The single failure a world native returns when it has no world to talk
    /// to, or no world identity for its receiver.
    static func needsWorld(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
        failure(call, "\(call.functionName) needs a world runtime and a reference receiver")
    }

    /// The failure for a reference whose plugin baseline no resident cell can
    /// supply, which is what stops a read from inventing a position.
    static func needsResidentReference(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
        failure(call, "\(call.functionName) needs a reference a resident cell knows")
    }

    /// Registers a native that reads or writes the script state of its receiver's form,
    /// or of the player for a global `Game` function.
    static func scriptState(
        _ script: String, _ name: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, PapyrusWorldStateBridge, ReferenceKey
        ) -> PapyrusNativeResult
    ) {
        let native: PapyrusNativeFunction.Body = { call, context in
            guard let bridge = context.world as? PapyrusWorldStateBridge else {
                return needsWorld(call)
            }
            if script == "Game" {
                return body(call, bridge, .player)
            }
            guard let key = call.receiver.flatMap(bridge.referenceKey(for:)) else {
                return needsWorld(call)
            }
            return body(call, bridge, key)
        }
        registry.register(PapyrusNativeFunction(
            scriptName: script,
            functionName: name,
            body: native
        ))
    }

    /// One record identity as the object value a script compares against, or
    /// Papyrus `None` when no handle can be minted for it.
    static func handle(_ key: ReferenceKey, in world: any PapyrusWorldBridge) -> PapyrusValue {
        world.objectHandle(for: key).map(PapyrusValue.object) ?? .none
    }
}
