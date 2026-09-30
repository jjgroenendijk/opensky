// `GlobalVariable` natives. A GLOB arrives as a VMAD object property and
// resolves like a reference. Writes go through `WorldStateStore.setGlobal`, which
// applies `Global.ValueType.coerce`: 3.7 into a short global stores 4.
// `Global.isConstant` is not enforced, because no open source says the game
// refuses a scripted write (docs/engine/papyrus-activation.md).

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    public static func installGlobalVariable(into registry: inout PapyrusNativeRegistry) {
        installGlobalReads(into: &registry)
        installGlobalWrites(into: &registry)
    }

    /// `float GetValue()` and `int GetValueInt()`. An undefined global fails
    /// rather than reading 0, because a script would act on the 0.
    /// `GetValueInt` truncates toward zero and saturates at the `Int32` bounds.
    private static func installGlobalReads(
        into registry: inout PapyrusNativeRegistry
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: "GlobalVariable",
            functionName: "GetValue"
        ) { call, context in
            guard let value = globalValue(call, context) else {
                return needsGlobal(call)
            }
            return .returned(.float(value.value))
        })
        registry.register(PapyrusNativeFunction(
            scriptName: "GlobalVariable",
            functionName: "GetValueInt"
        ) { call, context in
            guard let value = globalValue(call, context) else {
                return needsGlobal(call)
            }
            return .returned(.integer(integerValue(of: value.value)))
        })
    }

    /// `SetValue(float afNewValue)` and `SetValueInt(int aiNewValue)`.
    /// A write needs no existing definition, so a session with no `GlobalStore`
    /// can still store one. A non-finite value is refused, because coercion
    /// would turn it into 0 and hide the script's bug.
    private static func installGlobalWrites(
        into registry: inout PapyrusNativeRegistry
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: "GlobalVariable",
            functionName: "SetValue"
        ) { call, context in
            guard let target = worldTarget(call, context) else {
                return needsWorld(call)
            }
            guard let value = float(call, at: 0), value.isFinite else {
                return failure(call, "SetValue needs a finite number")
            }
            target.world.setGlobal(value, for: target.key)
            return .returned(.none)
        })
        registry.register(PapyrusNativeFunction(
            scriptName: "GlobalVariable",
            functionName: "SetValueInt"
        ) { call, context in
            guard let target = worldTarget(call, context) else {
                return needsWorld(call)
            }
            guard let value = integer(call, at: 0) else {
                return failure(call, "SetValueInt needs an integer")
            }
            target.world.setGlobal(Float(value), for: target.key)
            return .returned(.none)
        })
    }

    private static func globalValue(
        _ call: PapyrusNativeCall,
        _ context: PapyrusNativeContext
    ) -> GlobalValue? {
        guard let target = worldTarget(call, context) else { return nil }
        return target.world.globalValue(for: target.key)
    }

    private static func needsGlobal(
        _ call: PapyrusNativeCall
    ) -> PapyrusNativeResult {
        failure(call, "\(call.functionName) needs a global this session defines")
    }

    /// A global's float value as `GetValueInt` reports it: truncated toward
    /// zero, saturating instead of trapping. `Int32(exactly:)` is the check,
    /// because the largest `Int32` has no exact `Float`, so comparing against
    /// it first would round the bound up and overflow the conversion.
    private static func integerValue(of value: Float) -> Int32 {
        let truncated = value.rounded(.towardZero)
        if let exact = Int32(exactly: truncated) {
            return exact
        }
        guard !truncated.isNaN else { return 0 }
        return truncated < 0 ? Int32.min : Int32.max
    }
}
