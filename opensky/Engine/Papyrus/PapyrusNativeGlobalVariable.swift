// `GlobalVariable` natives (issue #172): the script side of the GLOB
// write-coercion seam in `opensky/Formats/ESM/Records/Global.swift`, which was
// written naming Papyrus as its caller.
//
// A `GlobalVariable` reaches script code as a VMAD object property, so its
// receiver handle resolves to a `ReferenceKey` exactly like a reference does;
// `PapyrusWorldStateBridge` maps that key back to the GLOB's FormID and writes
// through `WorldStateStore.setGlobal(_:formID:defaults:)`. The store applies
// `Global.ValueType.coerce`, so a write of 3.7 into a short or long global
// stores 4 and a read gives 4 back.
//
// `Global.isConstant` — record header flag 0x40 — is recorded by the decoder
// and deliberately not enforced here. The Creation Kit forbids *editing* a
// constant global in the editor, which is a design-time rule about authored
// data rather than a runtime one, and no open documentation states that the
// game engine refuses a scripted write. Refusing one would also need a second
// bridge method for a rule OpenSky cannot verify. So a scripted write to a
// constant global is applied and recorded like any other; the flag stays
// available for the Creation Kit-parity work that has a reason to consult it.

import Foundation

nonisolated extension PapyrusNativeFunctions {
    static func installGlobalVariable(into registry: inout PapyrusNativeRegistry) {
        installGlobalReads(into: &registry)
        installGlobalWrites(into: &registry)
    }

    /// `float GetValue()` and `int GetValueInt()`.
    ///
    /// A key nothing defines — no GLOB record and no override recorded this
    /// session — is a failure rather than a zero, because zero is a value a
    /// script would go on to act upon.
    ///
    /// `GetValueInt` on a float global truncates toward zero, matching how
    /// Papyrus casts a float to an int everywhere else, and saturates at the
    /// `Int32` bounds rather than trapping on a value no integer can hold.
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
    ///
    /// Unlike the reads these do not require the global to be defined already:
    /// in a session with no `GlobalStore` behind it the first write is what
    /// creates the override, and refusing it would make a synthetic session
    /// unable to store anything. A non-finite value is refused, because the
    /// coercion rule turns it into 0 and a script asking for NaN has a bug the
    /// tally should show.
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
