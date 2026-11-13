// `RegisterForSleep`, `OnSleepStart(afSleepStartTime, afDesiredSleepEndTime)`, and
// `OnSleepStop(abInterrupted)`. Only the instance that registered hears them (Creation
// Kit wiki "RegisterForSleep - Form"). See docs/engine/papyrus-registrations.md#sleep.

import Foundation
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime.ScriptEvents {
    /// False when `handle` names no script instance.
    @discardableResult
    func registerSleep(handle: PapyrusObjectHandle, _ isRegistered: Bool) -> Bool {
        guard let key = world.keysByHandle[handle] else { return false }
        if isRegistered {
            world.sleepListeners.insert(key)
        } else {
            world.sleepListeners.remove(key)
        }
        return true
    }

    /// OpenSky passes the hours at once, so the start and an uninterrupted stop queue
    /// together. Returns how many events were queued.
    @discardableResult
    public func queueSleepEvents(start: Double, end: Double) -> Int {
        world.sleepListeners = world.sleepListeners.filter { world.instancesByKey[$0] != nil }
        let listeners = world.sleepListeners.sorted()
        for listener in listeners {
            world.enqueue(PapyrusScriptEvent(
                target: listener, functionName: PapyrusEngineEvents.onSleepStart,
                arguments: [.float(Float(start)), .float(Float(end))], activationDepth: 0
            ))
            world.enqueue(PapyrusScriptEvent(
                target: listener, functionName: PapyrusEngineEvents.onSleepStop,
                arguments: [.boolean(false)], activationDepth: 0
            ))
        }
        return listeners.count * 2
    }
}

extension PapyrusNativeFunctions.SleepNatives {
    static func installSleep(into registry: inout PapyrusNativeRegistry) {
        for script in PapyrusNativeFunctions.UpdateTimersNatives.updateTimerScripts {
            for (name, isRegistered) in [("RegisterForSleep", true), (
                "UnregisterForSleep",
                false
            )] {
                registry.register(PapyrusNativeFunction(
                    scriptName: script, functionName: name
                ) { call, context in
                    guard
                        let bridge = context.world as? PapyrusWorldStateBridge,
                        let world = bridge.world, let receiver = call.receiver
                    else { return needsWorld(call) }
                    world.scriptEvents.registerSleep(handle: receiver, isRegistered)
                    return .returned(.none)
                })
            }
        }
    }
}
