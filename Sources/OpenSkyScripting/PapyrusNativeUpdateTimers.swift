// The `Form` update-timer natives: the `RegisterForUpdate` and
// `UnregisterForUpdate` families. They register under `Form`, where the Creation
// Kit declares them. A timer targets the calling script instance, not the whole
// reference; an opaque handle is a no-op. Slot rules live in
// `PapyrusWorldUpdateTimers.swift`.

import Foundation
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    public static func installUpdateTimers(into registry: inout PapyrusNativeRegistry) {
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
