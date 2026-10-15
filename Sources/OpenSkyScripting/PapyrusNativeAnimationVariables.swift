// `ObjectReference.GetAnimationVariable*` and `SetAnimationVariable*` (Creation Kit wiki
// "SetAnimationVariableBool - ObjectReference") read and write a variable of the
// object's behaviour graph. An object without that graph variable fails with a reason.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    static func installAnimationVariables(into registry: inout PapyrusNativeRegistry) {
        for type in ["Bool", "Int", "Float"] {
            animationVariable("GetAnimationVariable\(type)", into: &registry) { call, bridge, key in
                guard
                    let name = string(call, at: 0),
                    let value = bridge.animationVariable(name, on: key)
                else { return failure(call, "the object's graph has no such variable") }
                return .returned(converted(value, to: type))
            }
            animationVariable("SetAnimationVariable\(type)", into: &registry) { call, bridge, key in
                guard
                    let name = string(call, at: 0), call.arguments.count > 1,
                    bridge.setAnimationVariable(
                        name, to: converted(call.arguments[1], to: type), on: key
                    )
                else { return failure(call, "the object's graph has no such variable") }
                return .returned(.none)
            }
        }
    }

    /// A graph variable read in the type the native names, as Papyrus casts it.
    private static func converted(_ value: PapyrusValue, to type: String) -> PapyrusValue {
        let number: Float = switch value {
        case let .boolean(flag): flag ? 1 : 0
        case let .integer(integer): Float(integer)
        case let .float(float): float
        default: 0
        }
        return switch type {
        case "Bool": .boolean(number != 0)
        case "Int": .integer(Int32(max(min(number, Float(Int32.max - 128)), Float(Int32.min))))
        default: .float(number)
        }
    }

    private static func animationVariable(
        _ functionName: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, any PapyrusObjectAnimationBridge, ReferenceKey
        ) -> PapyrusNativeResult
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: "ObjectReference", functionName: functionName
        ) { call, context in
            guard
                let world = context.world as? PapyrusWorldStateBridge,
                let bridge = world.objectAnimation,
                let key = call.receiver.flatMap(world.referenceKey(for:))
            else { return failure(call, "\(functionName) needs an object with a graph") }
            return body(call, bridge, key)
        })
    }
}
