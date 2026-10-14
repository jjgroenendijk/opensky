// The update-timer natives: the `RegisterForUpdate` and `UnregisterForUpdate`
// families. `Alias` and `ActiveMagicEffect` extend no `Form`, so the Creation Kit
// declares the same natives on each of the three. A timer targets the calling
// script instance, not the whole reference; an opaque handle is a no-op. Slot rules live in
// `PapyrusWorldUpdateTimers.swift`.

import Foundation
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    static let updateTimerScripts = ["Form", "Alias", "ActiveMagicEffect"]

    public static func installUpdateTimers(into registry: inout PapyrusNativeRegistry) {
        let slots: [(String, PapyrusUpdateTimerSlot)] = [
            ("RegisterForUpdate", .realRepeating),
            ("RegisterForSingleUpdate", .realSingleShot),
            ("RegisterForUpdateGameTime", .gameTimeRepeating),
            ("RegisterForSingleUpdateGameTime", .gameTimeSingleShot)
        ]
        for script in updateTimerScripts {
            installUpdateTimers(on: script, slots: slots, into: &registry)
        }
    }

    private static func installUpdateTimers(
        on script: String,
        slots: [(String, PapyrusUpdateTimerSlot)],
        into registry: inout PapyrusNativeRegistry
    ) {
        for (functionName, slot) in slots {
            registry.register(PapyrusNativeFunction(
                scriptName: script,
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
                scriptName: script,
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
