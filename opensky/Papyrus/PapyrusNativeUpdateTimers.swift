// The `Form` update-timer natives (issue #277): `RegisterForUpdate`,
// `RegisterForSingleUpdate`, `RegisterForUpdateGameTime`,
// `RegisterForSingleUpdateGameTime`, `UnregisterForUpdate`, and
// `UnregisterForUpdateGameTime`.
//
// The Creation Kit declares this family on `Form`, so a compiled call from a
// script whose chain declares them native dispatches with scriptName "Form" —
// which is the key these register under. The interpreter's fallback for a
// function the loaded chain does not declare dispatches under the instance's
// root script name instead, so a load order that never provides `Form.pex`
// logs an unimplemented native rather than reaching these; that mirrors how
// the `ObjectReference` family already resolves.
//
// Registration targets the exact script instance making the call, not the
// whole reference: `PapyrusWorldRuntime.registerUpdateTimer(handle:)` maps
// the receiver handle to its one instance key, and an opaque handle (the
// player, an unscripted reference) is a no-op returning None. Interval
// semantics and slot rules live with the registry in
// `PapyrusWorldUpdateTimers.swift`.

import Foundation

nonisolated extension PapyrusNativeFunctions {
    static func installUpdateTimers(into registry: inout PapyrusNativeRegistry) {
        let slots: [(String, PapyrusUpdateTimerSlot)] = [
            ("RegisterForUpdate", .realRepeating),
            ("RegisterForSingleUpdate", .realSingleShot),
            ("RegisterForUpdateGameTime", .gameTimeRepeating),
            ("RegisterForSingleUpdateGameTime", .gameTimeSingleShot)
        ]
        for (functionName, slot) in slots {
            registry.register(PapyrusNativeFunction(
                scriptName: "Form",
                functionName: functionName
            ) { call, context in
                registerTimer(call, context, slot: slot)
            })
        }
        let families: [(String, PapyrusUpdateTimerFamily)] = [
            ("UnregisterForUpdate", .real),
            ("UnregisterForUpdateGameTime", .gameTime)
        ]
        for (functionName, family) in families {
            registry.register(PapyrusNativeFunction(
                scriptName: "Form",
                functionName: functionName
            ) { call, context in
                guard let world = context.world, let receiver = call.receiver else {
                    return needsWorld(call)
                }
                world.unregisterUpdateTimers(handle: receiver, family: family)
                return .returned(.none)
            })
        }
    }

    private static func registerTimer(
        _ call: PapyrusNativeCall,
        _ context: PapyrusNativeContext,
        slot: PapyrusUpdateTimerSlot
    ) -> PapyrusNativeResult {
        guard let world = context.world, let receiver = call.receiver else {
            return needsWorld(call)
        }
        guard let interval = float(call, at: 0) else {
            return failure(call, "\(call.functionName) needs a float interval")
        }
        world.registerUpdateTimer(
            handle: receiver, slot: slot, interval: Double(interval)
        )
        return .returned(.none)
    }
}
